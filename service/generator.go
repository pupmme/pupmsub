package service

import (
	"github.com/pupmme/pupmsub/db"
)

// Generator merges xboard inbound skeleton + node advanced settings → sing-box config.
// xboardInbound may be nil; local inbounds from DB are always merged.
func GenerateSingboxConfig(xboardInbound *db.InboundBasic) map[string]any {
	cfg := map[string]any{
		"log": map[string]any{
			"level": "warn",
		},
		"inbounds": []map[string]any{},
		"outbounds": []map[string]any{
			{"type": "direct", "tag": "direct"},
			{"type": "block", "tag": "block"},
			{"type": "dns", "tag": "dns-out"},
		},
		"route": map[string]any{
			"domain_strategy": "prefer_ipv4",
			"rules": []map[string]any{
				{"protocol": []string{"bittorrent"}, "outbound": "block"},
				{"port": []int{53}, "outbound": "dns-out"},
			},
		},
		"dns": map[string]any{
			"servers": []map[string]any{
				{"tag": "google", "address": "https://8.8.8.8/dns-query", "detour": "direct"},
				{"tag": "local", "address": "https://dns.aliyun.com/dns-query", "detour": "direct"},
				{"tag": "block", "address": "rcode://success"},
			},
		},
	}

	if xboardInbound != nil {
		inb := xboardInboundToSingbox(xboardInbound)
		adv := getInboundAdvanced(xboardInbound.Tag)
		mergeAdvanced(inb, adv)
		inbs := cfg["inbounds"].([]map[string]any)
		inbs = append(inbs, inb)
		cfg["inbounds"] = inbs
	}

	for _, ib := range db.GetInboundsBasic() {
		if ib.XboardTag == "" {
			inb := basicToSingboxInbound(&ib)
			adv := getInboundAdvanced(ib.Tag)
			mergeAdvanced(inb, adv)
			inbs := cfg["inbounds"].([]map[string]any)
			inbs = append(inbs, inb)
			cfg["inbounds"] = inbs
		}
	}

	mergeOutbounds(cfg)
	mergeDNS(cfg)

	cfg["experimental"] = map[string]any{
		"v2ray_api_access": []string{"127.0.0.1"},
	}

	return cfg
}

func xboardInboundToSingbox(ib *db.InboundBasic) map[string]any {
	inb := map[string]any{
		"tag":         ib.Tag,
		"type":        ib.Type,
		"listen":      "0.0.0.0",
		"listen_port": ib.Port,
	}
	if ib.UUID != "" {
		inb["uuid"] = ib.UUID
	}
	if ib.Password != "" {
		inb["password"] = ib.Password
	}
	return inb
}

func basicToSingboxInbound(ib *db.InboundBasic) map[string]any {
	return xboardInboundToSingbox(ib)
}

func getInboundAdvanced(tag string) *db.InboundAdvanced {
	for _, a := range db.GetInboundsAdv() {
		if a.Tag == tag {
			return &a
		}
	}
	return nil
}

func mergeAdvanced(inb map[string]any, adv *db.InboundAdvanced) {
	if adv == nil {
		return
	}

	inbType, _ := inb["type"].(string)

	// ---- Sniff (sing-box 1.13.6: must be object, not boolean) ----
	if isUDPFriendly(inbType) {
		inb["sniff"] = map[string]any{
			"enabled":              true,
			"override_destination": true,
		}
		inb["udp_timeout"] = 300
		inb["domain_strategy"] = "prefer_ipv4"
	}

	// ---- Multiplex inbound ----
	if adv.MultiplexInbound {
		inb["multiplex"] = map[string]any{
			"enabled":          true,
			"max_connections": 8,
			"padding_only":    false,
		}
	}

	// ---- Reality (sing-box 1.13.6: nested in tls.reality, server uses private_key) ----
	if adv.Reality.Enabled {
		tls, ok := inb["tls"].(map[string]any)
		if !ok {
			tls = map[string]any{}
			inb["tls"] = tls
		}
		tls["enabled"] = true
		tls["reality"] = map[string]any{
			"enabled":    true,
			"private_key": adv.Reality.PrivateKey,
			"short_id":   []string{adv.Reality.ShortID},
		}
		if adv.Reality.ServerName != "" {
			tls["server_name"] = adv.Reality.ServerName
		}
	}

	// ---- Mux ----
	if adv.Mux.Enabled {
		inb["multiplex"] = map[string]any{
			"enabled":          true,
			"max_connections": adv.Mux.MaxConnections,
		}
	}

	// ---- TUN (transparent proxy) ----
	if adv.TUN.Enabled {
		tun := map[string]any{
			"enabled": true,
		}
		if adv.TUN.InterfaceName != "" {
			tun["interface_name"] = adv.TUN.InterfaceName
		}
		if adv.TUN.Stack != "" {
			tun["stack"] = adv.TUN.Stack
		}
		if adv.TUN.MTU > 0 {
			tun["mtu"] = adv.TUN.MTU
		}
		if adv.TUN.AutoRoute {
			tun["auto_route"] = true
		}
		if adv.TUN.StrictRoute {
			tun["strict_route"] = true
		}
		tun["sniff"] = map[string]any{
			"enabled":              true,
			"override_destination": true,
		}
		inb["tun"] = tun
	}

	// ---- Obfs (Hysteria2 built-in obfuscation; also Shadowsocks plugin replacement) ----
	// sing-box 1.13.6 uses built-in obfs fields, not external plugin field.
	if adv.Obfs.Enabled {
		obfs := map[string]any{
			"type": adv.Obfs.Type,
		}
		if adv.Obfs.Password != "" {
			obfs["password"] = adv.Obfs.Password
		}
		inb["obfs"] = obfs
	}
}

func mergeOutbounds(cfg map[string]any) {
	obs := db.GetOutbounds()
	singOuts := cfg["outbounds"].([]map[string]any)

	for _, ob := range obs {
		switch ob.Type {
		case "selector":
			singOuts = append(singOuts, map[string]any{
				"type":     "selector",
				"tag":      ob.Tag,
				"outbounds": ob.Selector,
			})
		case "urltest":
			var servers []string
			for _, s := range ob.Servers {
				servers = append(servers, s.Server)
			}
			singOuts = append(singOuts, map[string]any{
				"type":     "urltest",
				"tag":      ob.Tag,
				"outbounds": servers,
				"url":      "http://www.gstatic.com/generate_204",
				"interval": "5m",
			})
		case "vmess", "vless", "trojan", "shadowsocks", "hysteria", "hysteria2", "tuic", "wireguard":
			singOuts = append(singOuts, outServerToSingbox(&ob))
		}
	}

	cfg["outbounds"] = singOuts
}

func outServerToSingbox(ob *db.Outbound) map[string]any {
	m := map[string]any{
		"tag":         ob.Tag,
		"type":        ob.Type,
		"server":      "",
		"server_port": 443,
	}
	for _, s := range ob.Servers {
		if s.Server != "" {
			m["server"] = s.Server
			m["server_port"] = s.Port
		}
		if s.UUID != "" {
			m["uuid"] = s.UUID
		}
		if s.Password != "" {
			m["password"] = s.Password
		}
		if s.Method != "" {
			m["method"] = s.Method
		}
		if s.Protocol != "" {
			m["protocol"] = s.Protocol
		}
	}
	return m
}

func isUDPFriendly(t string) bool {
	switch t {
	case "shadowsocks", "vmess", "vless", "trojan", "hysteria", "hysteria2",
		"tuic", "wireguard", "quic", "grpc":
		return true
	default:
		return false
	}
}

func mergeDNS(cfg map[string]any) {
	dnsCfg := db.GetDNS()
	if len(dnsCfg.Servers) == 0 {
		return
	}
	servers := []map[string]any{}
	for _, ds := range dnsCfg.Servers {
		s := map[string]any{
			"tag":     ds.Tag,
			"address": ds.Address,
		}
		if ds.Detour != "" {
			s["detour"] = ds.Detour
		}
		servers = append(servers, s)
	}
	cfg["dns"] = map[string]any{
		"servers":  servers,
		"strategy": dnsCfg.Strategy,
	}
}
