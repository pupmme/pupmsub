package network

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/pupmme/pupmsub/config"
)

type Client struct {
	baseURL string
	apiKey  string
	nodeID  int
	hc      *http.Client
	etag    string
}

func NewClient() *Client {
	cfg := config.Get()
	c := &Client{
		baseURL: cfg.APIHost,
		apiKey:  cfg.APIKey,
		nodeID:  cfg.NodeID,
		hc: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
	return c
}

func (c *Client) signRequest(method, path string) (token, timestamp string) {
	timestamp = strconv.FormatInt(time.Now().Unix(), 10)
	payload := method + path + timestamp
	mac := hmac.New(sha256.New, []byte(c.apiKey))
	mac.Write([]byte(payload))
	token = hex.EncodeToString(mac.Sum(nil))
	return
}

func (c *Client) doRequest(method, path string, body any) ([]byte, int, error) {
	token, ts := c.signRequest(method, path)
	req, err := http.NewRequest(method, c.baseURL+path, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Token", token)
	req.Header.Set("X-Token-Time", ts)
	if method == "GET" && c.etag != "" {
		req.Header.Set("If-None-Match", c.etag)
	}
	if body != nil {
		b, _ := json.Marshal(body)
		req.Body = io.NopCloser(strings.NewReader(string(b)))
		req.ContentLength = int64(len(b))
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("request: %w", err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusNotModified {
		return b, resp.StatusCode, nil
	}
	if resp.StatusCode != http.StatusOK {
		return b, resp.StatusCode, fmt.Errorf("status %d: %s", resp.StatusCode, string(b))
	}
	if etag := resp.Header.Get("ETag"); etag != "" {
		c.etag = etag
	}
	return b, resp.StatusCode, nil
}

func (c *Client) Handshake(runtimeVersion string) (*HandshakeResponse, error) {
	req := HandshakeRequest{
		NodeID:          c.nodeID,
		NodeKey:         c.apiKey,
		ListenIP:        "",
		RuntimeVersion:   runtimeVersion,
		ProtocolVersion: 2,
	}
	b, _, err := c.doRequest("POST", "/api/v2/server/handshake", req)
	if err != nil {
		return nil, err
	}
	var hs HandshakeResponse
	if err := json.Unmarshal(b, &hs); err != nil {
		return nil, fmt.Errorf("decode handshake: %w", err)
	}
	c.etag = "" // handshake success — invalidate etag
	return &hs, nil
}

func (c *Client) GetConfig() (*NodeConfig, error) {
	b, code, err := c.doRequest("GET", "/api/v2/server/config", nil)
	if err != nil {
		return nil, err
	}
	if code == http.StatusNotModified {
		return nil, nil // not modified
	}
	var cfg NodeConfig
	if err := json.Unmarshal(b, &cfg); err != nil {
		return nil, fmt.Errorf("decode config: %w", err)
	}
	return &cfg, nil
}

func (c *Client) GetUsers() ([]User, error) {
	b, _, err := c.doRequest("GET", "/api/v2/server/users", nil)
	if err != nil {
		return nil, err
	}
	var users []User
	if err := json.Unmarshal(b, &users); err != nil {
		return nil, fmt.Errorf("decode users: %w", err)
	}
	return users, nil
}

func (c *Client) ReportTraffic(req []TrafficRequest) error {
	_, _, err := c.doRequest("POST", "/api/v2/server/traffic", req)
	return err
}

func (c *Client) PushStatus(req *StatusRequest) error {
	_, _, err := c.doRequest("POST", "/api/v2/server/status", req)
	return err
}

func (c *Client) ResetETags() {
	c.etag = ""
}
