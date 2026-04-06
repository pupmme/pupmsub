package service

import (
	"github.com/pupmme/pupmsub/db"
)

// Generator merges xboard inbound skeleton + node advanced settings → sing-box config.
// xboardInbound may be nil; local inbounds from DB are always merged.
func GenerateSingboxConfig(xboardInbound *db.InboundBasic) map[string]any {
	// Start with base structure
	cfg := map[string]any{
		"log": map[string]any{
			"level": "warn",
		},
		"inbounds": []map[string]any{}{},
		"outbounds": []map[string]any{}{
			{ "type": "direct",   "tag": "direct" },
			{ "type": "block",    "tag": "block"  },
			{ "type": "dns",      "tag": "dns-out" },
		},
		"route": map[string]any{
			"domain_strategy": "prefer_ipv4",
			"rules": []map[string]any{}{
				{ "protocol": []string{"bittorrent"}, "outbound": "block" },
				{ "port":     []int{53},              "outbound": "dns-out" },
			},
		},
		"dns": map[string]any{
			"servers": []map[string]any{}{
				{ "tag": "google", "address": "https://8.8.8.8/dns-query", "detour": "proxy" },
				{ "tag": "local", "address": "https://dns.aliyun.com/dns-query", "detour": "direct" },
				{ "tag": "block", "address": "rcode://success" },
			},
		},
	}

	// Merge xboard inbound if provided
	if xboardInbound != nil {
		inb := xboardInboundToSingbox(xboardInbound)
		// merge with node advanced settings
		adv := getInboundAdvanced(xboardInbound.Tag)
		mergeAdvanced(inb, adv)
		inbs := cfg["inbounds"].([]map[string]any)
		inbs = append(inbs, inb)
		cfg["inbounds"] = inbs
	}

	// Merge local inbounds (not from xboard)
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

	// Merge outbounds
	mergeOutbounds(cfg)

	// Merge DNS
	mergeDNS(cfg)

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

	// ---- UDP session isolation (Fix: UDP tuple collision under multi-IP topology) ----
	// The root cause: when multiple outbound targets share a single internal IPv4
	// while inbound is scattered across multiple public IPv4s, conntrack fails to
	// demux returning UDP packets — causing concurrent map read/write panics or
	// cross-user routing. Fix: force deterministic 5-tuple resolution on all
	// UDP-friendly inbound types.
	inbType, _ := inb["type"].(string)
	if isUDPFriendly(inbType) {
		// sniff_override_destination: resolve destination before routing to prevent
		// conntrack tuple collision when multiple public IPs share a single outbound
		inb["sniff_override_destination"] = true
		// sniff: always on for UDP to ensure packet identity is preserved
		inb["sniff"] = true
		// udp_timeout: cap UDP session lifetime; prevents stale entries from piling up
		// in the conntrack table when multi-IP topology causes delayed responses
		inb["udp_timeout"] = 300
		// domain_strategy: use ipv4-only for UDP to avoid IPv6 path instability
		inb["domain_strategy"] = "prefer_ipv4"
	}
	// multiplex_inbound: for Shadowsocks (and other mux-capable protocols),
	// enables in-band connection multiplexing per inbound listener.
	// This provides user-level logical isolation within a single shared port,
	// preventing the "8 SS ports competing for UDP" failure scenario.
	if adv.MultiplexInbound {
		inb["multiplex"] = map[string]any{
			"enabled":       true,
			"max_connections": 8,
			"padding_only":   false,
		}
	}

	// uTLS fingerprint
	if adv.UTLS.Enabled {
		utls := map[string]any{"enabled": true}
		if adv.UTLS.Fingerprint != "" {
			utls["fingerprint"] = adv.UTLS.Fingerprint
		}
		inb["fingerprint"] = adv.UTLS.Fingerprint
	}

	// Reality
	if adv.Reality.Enabled {
		inb["reality"] = map[string]any{
			"enabled":    true,
			"public_key": adv.Reality.PublicKey,
			"short_id":   adv.Reality.ShortID,
			"server_name": adv.Reality.ServerName,
		}
	}

	// Mux
	if adv.Mux.Enabled {
		inb["multiplex"] = map[string]any{
			"enabled": true,
			"max_connections": adv.Mux.MaxConnections,
		}
	}

	// TUN
	if adv.TUN.Enabled {
		tun := map[string]any{
			"enabled": true,
		}
		if adv.TUN.InterfaceName != "" { tun["interface_name"] = adv.TUN.InterfaceName }
		if adv.TUN.Stack != ""        { tun["stack"] = adv.TUN.Stack }
		if adv.TUN.MTU > 0           { tun["mtu"] = adv.TUN.MTU }
		if adv.TUN.AutoRoute         { tun["auto_route"] = true }
		if adv.TUN.StrictRoute       { tun["strict_route"] = true }
		inb["sniff"] = true
		inb["sniff_override_destination"] = true
	}

	// Plugin (Shadowsocks)
	if adv.Plugin.Enabled && adv.Plugin.Name != "" {
		if _, ok := inb["plugin"]; !ok {
			inb["plugin"] = adv.Plugin.Name
		}
		if adv.Plugin.Opts != "" {
			// embed in settings or separate field
			inb["plugin_opts"] = adv.Plugin.Opts
		}
	}

	// Obfs (Hysteria2)
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
		"tag":    ob.Tag,
		"server": "",
		"server_port": 443,
	}
	for _, s := range ob.Servers {
		m["type"] = ob.Type
		m["server"] = s.Server
		m["server_port"] = s.Port
		if s.UUID != ""     { m["uuid"] = s.UUID }
		if s.Password != "" { m["password"] = s.Password }
		if s.Method != ""    { m["method"] = s.Method }
	}
	return m
}

// isUDPFriendly returns true for inbound types that use UDP for data transport.
// These types are susceptible to conntrack tuple collision under multi-IP topologies.
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
		"servers": servers,
		"strategy": dnsCfg.Strategy,
	}
}
