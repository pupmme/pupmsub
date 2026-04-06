package db

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"

	"github.com/pupmme/pupmsub/config"
)

// Store is the typed in-memory store backed by a single JSON file per key.
type Store[T any] struct {
	mu  sync.RWMutex
	val *T
	fn  string
}

func New[T any](filename string) *Store[T] {
	s := &Store[T]{fn: filename}
	s.load()
	return s
}

func (s *Store[T]) load() {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, err := os.ReadFile(s.fn)
	if err != nil || len(b) == 0 {
		s.val = new(T)
		return
	}
	t := new(T)
	if err := json.Unmarshal(b, t); err != nil {
		s.val = new(T)
		return
	}
	s.val = t
}

func (s *Store[T]) Get() T {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return *s.val
}

// GetConfig returns the global config (separate from the generic Store).

func (s *Store[T]) Set(val T) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.val = &val
}

func (s *Store[T]) Save() error {
	s.mu.RLock()
	defer s.mu.RUnlock()
	os.MkdirAll(filepath.Dir(s.fn), 0755)
	b, err := json.MarshalIndent(s.val, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.fn + ".tmp"
	if err := os.WriteFile(tmp, b, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, s.fn)
}

// Init creates all store files under the data directory.
func Init(dir string) {
	os.MkdirAll(dir, 0755)
}

// ---- Store singletons ----

var (
	muCfg   sync.RWMutex
	cfgData = struct {
		XboardHost string `json:"xboard_host"`
		APIKey     string `json:"api_key"`
		NodeID     int    `json:"node_id"`
	}{}

// GetConfigYaml reads the raw config.yaml for the settings API endpoint.
func GetConfigYaml() (data any) {
	muCfg.RLock()
	defer muCfg.RUnlock()
	return cfgData
}

	muIB   sync.RWMutex
	inbBas = New[[]InboundBasic](filepath.Join(config.DefaultConfigDir(), "inbounds_basic.json"))
	inbAdv = New[[]InboundAdvanced](filepath.Join(config.DefaultConfigDir(), "inbounds_advanced.json"))

	muRules sync.RWMutex
	rules   = New[[]Rule](filepath.Join(config.DefaultConfigDir(), "rules.json"))

	muOB sync.RWMutex
	obs  = New[[]Outbound](filepath.Join(config.DefaultConfigDir(), "outbounds.json"))

	muDNS sync.RWMutex
	dns   = New[DNSConfig](filepath.Join(config.DefaultConfigDir(), "dns.json"))

	muTLS sync.RWMutex
	tls   = New[TLSConfig](filepath.Join(config.DefaultConfigDir(), "tls.json"))

	muSvc sync.RWMutex
	svc   = New[map[string]any](filepath.Join(config.DefaultConfigDir(), "services.json"))

	muUR sync.RWMutex
	urs   = New[[]UserRule](filepath.Join(config.DefaultConfigDir(), "users_rules.json"))

	muTS sync.RWMutex
	tsnap = New[map[int64][2]int64](filepath.Join(config.DefaultConfigDir(), "traffic_snap.json"))

	muEP sync.RWMutex
	eps  = New[[]string](filepath.Join(config.DefaultConfigDir(), "endpoints.json"))
)

func GetInboundsBasic() []InboundBasic   { return inbBas.Get() }
func SetInboundsBasic(v []InboundBasic)  { inbBas.Set(v); inbBas.Save() }
func GetInboundsAdv() []InboundAdvanced  { return inbAdv.Get() }
func SetInboundsAdv(v []InboundAdvanced) { inbAdv.Set(v); inbAdv.Save() }
func GetRules() []Rule                   { return rules.Get() }
func SetRules(v []Rule)                  { rules.Set(v); rules.Save() }
func GetOutbounds() []Outbound           { return obs.Get() }
func SetOutbounds(v []Outbound)          { obs.Set(v); obs.Save() }
func GetDNS() DNSConfig                  { return dns.Get() }
func SetDNS(v DNSConfig)                 { dns.Set(v); dns.Save() }
func GetTLS() TLSConfig                  { return tls.Get() }
func SetTLS(v TLSConfig)                 { tls.Set(v); tls.Save() }
func GetServices() map[string]any       { return svc.Get() }
func SetServices(v map[string]any)     { svc.Set(v); svc.Save() }
func GetUserRules() []UserRule           { return urs.Get() }
func SetUserRules(v []UserRule)          { urs.Set(v); urs.Save() }
func GetTrafficSnap() map[int64][2]int64 { return tsnap.Get() }
func SetTrafficSnap(v map[int64][2]int64) { tsnap.Set(v); tsnap.Save() }
func GetEndpoints() []string              { return eps.Get() }
func SetEndpoints(v []string)            { eps.Set(v); eps.Save() }

// ---- Data types ----

type InboundBasic struct {
	Tag        string `json:"tag"`
	Type       string `json:"type"`
	Listen     string `json:"listen"`
	Port       int    `json:"port"`
	UUID       string `json:"uuid,omitempty"`
	Password   string `json:"password,omitempty"`
	XboardTag  string `json:"xboard_tag,omitempty"` // xboard inbound tag
	Users      []User `json:"users,omitempty"`
}

type InboundAdvanced struct {
	Tag    string       `json:"tag"`
	UTLS   UTLSConfig   `json:"utls,omitempty"`
	Reality RealityConfig `json:"reality,omitempty"`
	Plugin PluginConfig  `json:"plugin,omitempty"`
	Obfs   ObfsConfig   `json:"obfs,omitempty"`
	Mux    MuxConfig    `json:"mux,omitempty"`
	TUN    TUNConfig    `json:"tun,omitempty"`
	MultiplexInbound bool `json:"multiplex_inbound,omitempty"`
}

type UTLSConfig struct {
	Enabled    bool   `json:"enabled"`
	Fingerprint string `json:"fingerprint,omitempty"` // chrome/firefox/safari/android/edge/random
}

type RealityConfig struct {
	Enabled    bool   `json:"enabled"`
	PublicKey  string `json:"public_key,omitempty"`
	ShortID    string `json:"short_id,omitempty"`
	ServerName string `json:"server_name,omitempty"`
}

type PluginConfig struct {
	Enabled bool   `json:"enabled"`
	Name    string `json:"name,omitempty"` // v2ray-plugin / obfs-server
	Opts    string `json:"opts,omitempty"`
}

type ObfsConfig struct {
	Enabled  bool   `json:"enabled"`
	Type     string `json:"type,omitempty"` // salamander / http
	Password string `json:"password,omitempty"`
}

type MuxConfig struct {
	Enabled        bool `json:"enabled"`
	MaxConnections int  `json:"max_connections,omitempty"`
}

type TUNConfig struct {
	Enabled      bool   `json:"enabled"`
	InterfaceName string `json:"interface_name,omitempty"` // tun0
	Stack        string `json:"stack,omitempty"`         // system/gviso/mixed
	MTU          int    `json:"mtu,omitempty"`
	AutoRoute    bool   `json:"auto_route,omitempty"`
	StrictRoute  bool   `json:"strict_route,omitempty"`
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
}

type Rule struct {
	Type        string   `json:"type"` // domain/ip_cidr/port/protocol/inbound_tag/user/rule_set
	Domain      []string `json:"domain,omitempty"`
	DomainSuffix []string `json:"domain_suffix,omitempty"`
	DomainKeyword []string `json:"domain_keyword,omitempty"`
	IPCIDR     []string `json:"ip_cidr,omitempty"`
	Port       []int    `json:"port,omitempty"`
	PortRange  []string `json:"port_range,omitempty"`
	Network    []string `json:"network,omitempty"`
	Protocol   []string `json:"protocol,omitempty"`
	InboundTag []string `json:"inbound_tag,omitempty"`
	AuthUser   []string `json:"auth_user,omitempty"`
	RuleSet    []string `json:"rule_set,omitempty"`
	Outbound   string   `json:"outbound"`
}

type Outbound struct {
	Tag     string         `json:"tag"`
	Type    string         `json:"type"`
	Servers []OutServer    `json:"servers,omitempty"`
	Selector []string      `json:"selector,omitempty"` // for selector type
	Direct   *DirectConfig  `json:"direct,omitempty"`
}

type OutServer struct {
	Type      string `json:"type"`
	Server    string `json:"server"`
	Port      int    `json:"port"`
	UUID      string `json:"uuid,omitempty"`
	Password  string `json:"password,omitempty"`
	Method    string `json:"method,omitempty"`
	Protocol  string `json:"protocol,omitempty"`
}

type DirectConfig struct {
	Dialer     string `json:"dialer,omitempty"`
	Masquerade string `json:"masquerade,omitempty"`
}

type DNSConfig struct {
	Strategy     string      `json:"strategy,omitempty"` // prefer_ipv4/prefer_ipv6/AsIs
	ClientSubnet string      `json:"client_subnet,omitempty"`
	CacheCapacity int       `json:"cache_capacity,omitempty"`
	DisableCache bool       `json:"disable_cache"`
	DisableExpire bool      `json:"disable_expire"`
	Servers     []DNSServer `json:"servers,omitempty"`
	Rules       []DNSRule   `json:"rules,omitempty"`
}

type DNSServer struct {
	Tag     string `json:"tag"`
	Type    string `json:"type"` // doh/dot/doq/rcode/local/block
	Address string `json:"address"`
	Detour  string `json:"detour,omitempty"`
}

type DNSRule struct {
	Type        string   `json:"type"`
	InboundTag  []string `json:"inbound_tag,omitempty"`
	AuthUser   []string `json:"auth_user,omitempty"`
	QueryType  []string `json:"query_type,omitempty"`
	Domain     []string `json:"domain,omitempty"`
	IPCIDR     []string `json:"ip_cidr,omitempty"`
	Outbound   string   `json:"outbound"`
}

type TLSConfig struct {
	Enabled       bool              `json:"enabled"`
	ACME          ACMEConfig        `json:"acme,omitempty"`
	ECh           EChConfig        `json:"ech,omitempty"`
}

type ACMEConfig struct {
	Enabled         bool              `json:"enabled"`
	DataPath        string            `json:"data_path,omitempty"`
	DefaultServer   string            `json:"default_server,omitempty"`
	DefaultSNI      string            `json:"default_sni,omitempty"`
	PreferredChain  string            `json:"preferred_chain,omitempty"`
	HTTPChallenge   bool             `json:"http_challenge"`
	TLSALPNChallenge bool           `json:"tls_alpn_challenge"`
	DNSChallenge    bool             `json:"dns_challenge"`
	Providers       map[string]ProviderConfig `json:"providers,omitempty"`
}

type ProviderConfig struct {
	Provider string            `json:"provider"` // cloudflare/alidns/tencentcloud/route53/godaddy
	Env      map[string]string `json:"env"`       // API keys injected as env vars
}

type EChConfig struct {
	Enabled bool   `json:"enabled"`
	PublicKey string `json:"public_key,omitempty"`
}

type UserRule struct {
	Email    string `json:"email"`
	Outbound string `json:"outbound"`
	Priority int    `json:"priority"`
}
