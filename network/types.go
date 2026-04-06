package network

// xboard v2 protocol types

type HandshakeRequest struct {
	NodeID           int    `json:"node_id"`
	NodeKey          string `json:"node_key"`
	ListenIP         string `json:"listen_ip"`
	RuntimeVersion   string `json:"runtime_version"`
	ProtocolVersion  int    `json:"protocol_version"`
}

type HandshakeResponse struct {
	Version string         `json:"version"`
	Config  *NodeConfig    `json:"config,omitempty"`
	Users   []User         `json:"users,omitempty"`
}

type NodeConfig struct {
	Tag      string            `json:"tag"`
	Type     string            `json:"type"`
	Port     int               `json:"port"`
	Listen   string            `json:"listen"`
	Settings map[string]any    `json:"settings,omitempty"`
	TLS      map[string]any    `json:"tls,omitempty"`
}

type User struct {
	ID         int64   `json:"id"`
	Email      string  `json:"email"`
	UUID       string  `json:"uuid"`
	Enable     bool    `json:"enable"`
	Up         int64   `json:"up"`
	Down       int64   `json:"down"`
	Total      int64   `json:"total"`
	ExpiryTime int64   `json:"expiry_time"`
	SubID      string  `json:"sub_id,omitempty"`
	TgID       string  `json:"tg_id,omitempty"`
}

type TrafficRequest struct {
	NodeID int64 `json:"node_id"`
	UserID int64 `json:"user_id"`
	U      int64 `json:"u"`
	D      int64 `json:"d"`
}

type StatusRequest struct {
	CPU  float64          `json:"cpu"`
	Mem  [2]uint64        `json:"mem"`  // [total, used]
	Swap [2]uint64        `json:"swap"`
	Disk [2]uint64        `json:"disk"` // [total, used]
	Uptime int64          `json:"uptime"`
	Load   [3]float64     `json:"load"`  // [1m, 5m, 15m]
}
