package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/pupmme/pupmsub/config"
	"github.com/pupmme/pupmsub/db"
	"github.com/pupmme/pupmsub/logger"
	"github.com/pupmme/pupmsub/service"
)

// ---- Session store & token helpers (package-level) ----

var (
	// sessions maps the base64-encoded token header → expiry.
	sessions   = make(map[string]time.Time)
	sessionsMu sync.RWMutex
)

// signToken returns HMAC-SHA256 of "tag|expiry|" using the given secret.
func signToken(tag string, expiry int64, secret []byte) string {
	h := hmac.New(sha256.New, secret)
	h.Write([]byte(fmt.Sprintf("%s|%d|", tag, expiry)))
	return base64.RawURLEncoding.EncodeToString(h.Sum(nil))
}

// validToken verifies HMAC signature, expiry, and that the token is still live.
func validToken(token string, secret []byte) bool {
	parts := strings.SplitN(token, ".", 2)
	if len(parts) != 2 {
		return false
	}
	h := hmac.New(sha256.New, secret)
	h.Write([]byte(parts[0] + "."))
	expected := base64.RawURLEncoding.EncodeToString(h.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(parts[1])) {
		return false
	}
	var hdr struct {
		Tag    string `json:"tag"`
		Expiry int64  `json:"exp"`
	}
	if err := json.Unmarshal([]byte(parts[0]), &hdr); err != nil {
		return false
	}
	if hdr.Expiry < time.Now().Unix() {
		return false
	}
	sessionsMu.RLock()
	_, ok := sessions[parts[0]]
	sessionsMu.RUnlock()
	return ok
}

//go:embed tmpl
var tmplFS embed.FS

var tmpl = template.Must(template.ParseFS(tmplFS,
	"tmpl/index.html",
	"tmpl/inbounds.html",
	"tmpl/outbounds.html",
	"tmpl/views.html",
	"tmpl/protocol-engine.html",
))

var Version = "1.0.0"

func RunServer() {
	cfg := config.Get()
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	// SPA: all non-API routes → index.html
	r.NoRoute(func(c *gin.Context) {
		c.Header("Content-Type", "text/html; charset=utf-8")
		tmpl.ExecuteTemplate(c.Writer, "index", nil)
	})

	// ---- API routes ----
	api := r.Group("/api")

	// Public
	api.POST("/auth/login", handleLogin)

	// Auth-gated
	api.Use(func(c *gin.Context) {
		cfg := config.Get()
		if cfg.Username != "" && cfg.Password != "" {
			secret := []byte(cfg.Password)
			cookie, err := c.Cookie("pupmsub_session")
			if err != nil || !validToken(cookie, secret) {
				c.JSON(http.StatusUnauthorized, gin.H{"success": false, "msg": "unauthorized"})
				c.Abort()
				return
			}
		}
		c.Next()
	})

	api.GET("/status", handleStatus)
	api.GET("/inbounds", handleInbounds)
	api.POST("/inbounds", handleInboundsPost)
	api.PUT("/inbounds/*tag", handleInboundsPut)
	api.DELETE("/inbounds/*tag", handleInboundsDelete)
	api.GET("/inbounds/advanced", handleInboundsAdv)
	api.PUT("/inbounds/advanced", handleInboundsAdvPut)
	api.GET("/users", handleUsers)
	api.GET("/rules", handleRules)
	api.PUT("/rules", handleRulesPut)
	api.DELETE("/rules/*key", handleRulesDelete)
	api.GET("/users-rules", handleUsersRules)
	api.PUT("/users-rules", handleUsersRulesPut)
	api.GET("/outbounds", handleOutbounds)
	api.PUT("/outbounds/*tag", handleOutboundsPut)
	api.DELETE("/outbounds/*tag", handleOutboundsDelete)
	api.GET("/dns", handleDNS)
	api.PUT("/dns", handleDNSPut)
	api.GET("/tls", handleTLS)
	api.PUT("/tls", handleTLSPut)
	api.GET("/services", handleServices)
	api.PUT("/services", handleServicesPut)
	api.GET("/endpoints", handleEndpoints)
	api.PUT("/endpoints", handleEndpointsPut)
	api.GET("/config", handleConfig)
	api.PUT("/config", handleConfigPut)
	api.GET("/settings", handleSettings)
	api.PUT("/settings", handleSettingsPut)
	api.GET("/traffic", handleTraffic)
	api.GET("/logs", handleLogs)
	api.DELETE("/logs", handleLogsDelete)
	api.POST("/xboard/sync", handleXboardSync)
	api.POST("/singbox/restart", handleSingboxRestart)
	api.GET("/version", handleVersion)
	api.GET("/all-tags", handleAllTags)

	addr := ":" + cfg.WebPort
	logger.InfoCompat("HTTP server listening on", "addr", addr)
	http.ListenAndServe(addr, r)
}

// ============================================================
// Auth
// ============================================================

func handleLogin(c *gin.Context) {
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	cfg := config.Get()
	if req.Username != cfg.Username || req.Password != cfg.Password {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "msg": "invalid credentials"})
		return
	}
	// Sign a tamper-proof session token: base64(tag={'username','exp'}).HMAC-SHA256
	expiry := time.Now().Unix() + int64(3600*24)
	hdr, _ := json.Marshal(map[string]any{"tag": req.Username, "exp": expiry})
	token := base64.RawURLEncoding.EncodeToString(hdr) + "." + signToken(base64.RawURLEncoding.EncodeToString(hdr), expiry, []byte(cfg.Password))

	sessionsMu.Lock()
	sessions[base64.RawURLEncoding.EncodeToString(hdr)] = time.Now().Add(24 * time.Hour)
	sessionsMu.Unlock()

	c.SetCookie("pupmsub_session", token, 3600*24, "/", "", false, true)
	c.JSON(http.StatusOK, gin.H{"success": true, "msg": "ok"})
}

// ============================================================
// Status
// ============================================================

func handleStatus(c *gin.Context) {
	d := service.GetDaemon()
	if d == nil {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"obj": gin.H{
				"connected":   false,
				"singbox":     false,
				"onlineUsers": 0,
				"nodeId":      config.Get().NodeID,
				"info":        gin.H{"nodeType": config.Get().NodeType, "apiHost": config.Get().APIHost},
			},
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": d.GetStatus()})
}

// ============================================================
// Inbounds
// ============================================================

func handleInbounds(c *gin.Context) {
	basic := db.GetInboundsBasic()
	adv := db.GetInboundsAdv()
	advMap := make(map[string]db.InboundAdvanced)
	for _, a := range adv {
		advMap[a.Tag] = a
	}
	type InboundView struct {
		db.InboundBasic
		Adv db.InboundAdvanced `json:"advanced,omitempty"`
	}
	result := make([]InboundView, len(basic))
	for i, b := range basic {
		result[i] = InboundView{InboundBasic: b, Adv: advMap[b.Tag]}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": result})
}

func handleInboundsPost(c *gin.Context) {
	var ib db.InboundBasic
	if err := c.ShouldBindJSON(&ib); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	if ib.Tag == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": "tag 不能为空"})
		return
	}
	ibs := db.GetInboundsBasic()
	for _, existing := range ibs {
		if existing.Tag == ib.Tag {
			c.JSON(http.StatusConflict, gin.H{"success": false, "msg": "tag 已存在"})
			return
		}
	}
	ibs = append(ibs, ib)
	db.SetInboundsBasic(ibs)
	applyAndRestart(c)
}

func handleInboundsPut(c *gin.Context) {
	tag := strings.TrimPrefix(c.Param("tag"), "/")
	var ib db.InboundBasic
	if err := c.ShouldBindJSON(&ib); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	ibs := db.GetInboundsBasic()
	found := false
	for i, existing := range ibs {
		if existing.Tag == tag {
			ibs[i] = ib
			found = true
			break
		}
	}
	if !found {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "msg": "inbound not found"})
		return
	}
	db.SetInboundsBasic(ibs)
	applyAndRestart(c)
}

func handleInboundsDelete(c *gin.Context) {
	tag := strings.TrimPrefix(c.Param("tag"), "/")
	ibs := db.GetInboundsBasic()
	filtered := ibs[:0]
	for _, ib := range ibs {
		if ib.Tag != tag {
			filtered = append(filtered, ib)
		}
	}
	db.SetInboundsBasic(filtered)
	applyAndRestart(c)
}

func handleInboundsAdv(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetInboundsAdv()})
}

func handleInboundsAdvPut(c *gin.Context) {
	var ibs []db.InboundAdvanced
	if err := c.ShouldBindJSON(&ibs); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	db.SetInboundsAdv(ibs)
	applyAndRestart(c)
}

// ============================================================
// Users
// ============================================================

func handleUsers(c *gin.Context) {
	snap := db.GetTrafficSnap()
	allUsers := db.GetUsers()
	type UserInfo struct {
		ID         int64  `json:"id"`
		Email      string `json:"email"`
		Enable     bool   `json:"enable"`
		Up         int64  `json:"up"`
		Down       int64  `json:"down"`
		Total      int64  `json:"total"`
		ExpiryTime int64  `json:"expiry_time"`
	}
	result := []UserInfo{}
	for _, u := range allUsers {
		result = append(result, UserInfo{
			ID:    u.ID,
			Email: u.Email,
			Enable: u.Enable,
			Up:    snap[u.ID][0],
			Down:  snap[u.ID][1],
			Total: u.Total,
			ExpiryTime: u.ExpiryTime,
		})
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": result})
}

// ============================================================
// Rules
// ============================================================

func handleRules(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetRules()})
}

func handleRulesPut(c *gin.Context) {
	var rules []db.Rule
	if err := c.ShouldBindJSON(&rules); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	db.SetRules(rules)
	applyAndRestart(c)
}

func handleRulesDelete(c *gin.Context) {
	key := strings.TrimPrefix(c.Param("key"), "/")
	rules := db.GetRules()
	filtered := rules[:0]
	for _, r := range rules {
		if r.Type != key {
			filtered = append(filtered, r)
		}
	}
	db.SetRules(filtered)
	applyAndRestart(c)
}

// ============================================================
// User Rules
// ============================================================

func handleUsersRules(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetUserRules()})
}

func handleUsersRulesPut(c *gin.Context) {
	var urs []db.UserRule
	if err := c.ShouldBindJSON(&urs); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	db.SetUserRules(urs)
	applyAndRestart(c)
}

// ============================================================
// Outbounds
// ============================================================

func handleOutbounds(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetOutbounds()})
}

func handleOutboundsPut(c *gin.Context) {
	tag := strings.TrimPrefix(c.Param("tag"), "/")
	var ob db.Outbound
	if err := c.ShouldBindJSON(&ob); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	if ob.Tag == "" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": "tag 不能为空"})
		return
	}
	obs := db.GetOutbounds()
	found := false
	for i, existing := range obs {
		if existing.Tag == tag {
			obs[i] = ob
			found = true
			break
		}
	}
	if !found {
		obs = append(obs, ob)
	}
	db.SetOutbounds(obs)
	applyAndRestart(c)
}

func handleOutboundsDelete(c *gin.Context) {
	tag := strings.TrimPrefix(c.Param("tag"), "/")
	obs := db.GetOutbounds()
	filtered := obs[:0]
	for _, ob := range obs {
		if ob.Tag != tag {
			filtered = append(filtered, ob)
		}
	}
	db.SetOutbounds(filtered)
	applyAndRestart(c)
}

// ============================================================
// DNS
// ============================================================

func handleDNS(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetDNS()})
}

func handleDNSPut(c *gin.Context) {
	var dns db.DNSConfig
	if err := c.ShouldBindJSON(&dns); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	db.SetDNS(dns)
	applyAndRestart(c)
}

// ============================================================
// TLS
// ============================================================

func handleTLS(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetTLS()})
}

func handleTLSPut(c *gin.Context) {
	var tls db.TLSConfig
	if err := c.ShouldBindJSON(&tls); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	db.SetTLS(tls)
	applyAndRestart(c)
}

// ============================================================
// Services
// ============================================================

func handleServices(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetServices()})
}

func handleServicesPut(c *gin.Context) {
	var svc map[string]interface{}
	if err := c.ShouldBindJSON(&svc); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	db.SetServices(svc)
	applyAndRestart(c)
}

// ============================================================
// Endpoints
// ============================================================

func handleEndpoints(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetEndpoints()})
}

func handleEndpointsPut(c *gin.Context) {
	var eps []string
	if err := c.ShouldBindJSON(&eps); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	db.SetEndpoints(eps)
	applyAndRestart(c)
}

// ============================================================
// Config
// ============================================================

func handleConfig(c *gin.Context) {
	cfg := config.Get()
	b, err := os.ReadFile(cfg.SingboxConfig)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "msg": "config not found"})
		return
	}
	c.Data(http.StatusOK, "application/json", b)
}

func handleConfigPut(c *gin.Context) {
	var sbCfg map[string]interface{}
	if err := c.ShouldBindJSON(&sbCfg); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "msg": err.Error()})
		return
	}
	sb := service.GetSingbox()
	if sb == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"success": false, "msg": "singbox not init"})
		return
	}
	if err := sb.WriteConfig(sbCfg); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "msg": err.Error()})
		return
	}
	sb.Restart()
	c.JSON(http.StatusOK, gin.H{"success": true, "msg": "ok"})
}

// ============================================================
// Settings
// ============================================================

func handleSettings(c *gin.Context) {
	cfg := config.Get()
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": gin.H{
		"api_host":            cfg.APIHost,
		"api_key":            cfg.APIKey,
		"node_id":            cfg.NodeID,
		"node_type":          cfg.NodeType,
		"binary_path":        cfg.BinaryPath,
		"config_path":        cfg.SingboxConfig,
		"data_dir":           cfg.DataDir,
		"log_level":          cfg.LogLevel,
		"web_port":           cfg.WebPort,
		"username":           cfg.Username,
		"heartbeat_interval": cfg.HeartbeatInterval,
		"sync_interval":      cfg.SyncInterval,
	}})
}

func handleSettingsPut(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "msg": "settings saved"})
}

// ============================================================
// Traffic
// ============================================================

func handleTraffic(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": db.GetTrafficSnap()})
}

// ============================================================
// Logs
// ============================================================

func handleLogs(c *gin.Context) {
	cfg := config.Get()
	// FIX-4: use tail to read only last 200 lines — never load entire file into memory
	out, err := exec.Command("tail", "-n", "200", cfg.LogPath).Output()
	if err != nil {
		// fallback: read last 4KB if tail is unavailable
		f, err := os.Open(cfg.LogPath)
		if err != nil {
			c.JSON(http.StatusOK, gin.H{"success": true, "logs": ""})
			return
		}
		defer f.Close()
		fi, _ := f.Stat()
		if fi.Size() > 4096 {
			f.Seek(-4096, io.SeekEnd)
		}
		b, _ := io.ReadAll(f)
		c.JSON(http.StatusOK, gin.H{"success": true, "logs": strings.Join(tailLines(string(b), 200), "\n")})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "logs": strings.Join(tailLines(string(out), 200), "\n")})
}

func handleLogsDelete(c *gin.Context) {
	cfg := config.Get()
	os.WriteFile(cfg.LogPath, []byte(""), 0644)
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// ============================================================
// Xboard / Singbox actions
// ============================================================

func handleXboardSync(c *gin.Context) {
	d := service.GetDaemon()
	if d == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"success": false, "msg": "daemon not running"})
		return
	}
	go d.ForceSync()
	c.JSON(http.StatusOK, gin.H{"success": true, "msg": "同步已触发"})
}

func handleSingboxRestart(c *gin.Context) {
	sb := service.GetSingbox()
	if sb == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"success": false, "msg": "singbox not init"})
		return
	}
	if err := sb.Restart(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "msg": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "msg": "ok"})
}

// ============================================================
// Version / All Tags
// ============================================================

func handleVersion(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"success": true, "version": Version})
}

func handleAllTags(c *gin.Context) {
	obs := db.GetOutbounds()
	tags := make([]string, len(obs))
	for i, ob := range obs {
		tags[i] = ob.Tag
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "obj": tags})
}

// ============================================================
// Helpers
// ============================================================

func applyAndRestart(c *gin.Context) {
	sb := service.GetSingbox()
	if sb == nil {
		c.JSON(http.StatusOK, gin.H{"success": true, "msg": "ok (singbox not running)"})
		return
	}
	cfg := service.GenerateSingboxConfig()
	if err := sb.WriteConfig(cfg); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "msg": err.Error()})
		return
	}
	sb.Restart()
	c.JSON(http.StatusOK, gin.H{"success": true, "msg": "ok"})
}

func tailLines(s string, n int) []string {
	if n <= 0 {
		n = 100
	}
	lines := []string{}
	start := len(s)
	for i := len(s) - 1; i >= 0 && len(lines) < n; i-- {
		if s[i] == '\n' {
			lines = append([]string{s[i+1 : start]}, lines...)
			start = i
		}
	}
	if start > 0 && len(lines) < n {
		lines = append([]string{s[:start]}, lines...)
	}
	return lines
}
