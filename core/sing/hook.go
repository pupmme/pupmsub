package sing

import (
	"context"
	"net"
	"sync"

	"github.com/inazumav/sing-box/common/urltest"

	"github.com/InazumaV/V2bX/common/rate"

	"github.com/InazumaV/V2bX/common/counter"
	"github.com/inazumav/sing-box/adapter"
	"github.com/inazumav/sing-box/log"
	N "github.com/sagernet/sing/common/network"
)

// GetAllNodeStats returns traffic counters and connection counts for all nodes.
func (h *HookServer) GetAllNodeStats() map[string]struct{ Up, Down int64 } {
	stats := make(map[string]struct{ Up, Down int64 })
	h.counter.Range(func(key, value interface{}) bool {
		tag := key.(string)
		c := value.(*counter.TrafficCounter)
		snap := c.Snapshot()
		var up, down int64
		for _, s := range snap {
			up += s.Up
			down += s.Down
		}
		_ = c // suppress unused warning
		stats[tag] = struct{ Up, Down int64 }{Up: up, Down: down}
		return true
	})
	return stats
}

// GetCounter returns the TrafficCounter for a specific node tag (for metrics pull).
func (h *HookServer) GetCounter(tag string) *counter.TrafficCounter {
	if c, ok := h.counter.Load(tag); ok {
		return c.(*counter.TrafficCounter)
	}
	return nil
}

// CounterLen returns the number of tracked connections for a node.
func (h *HookServer) CounterLen(tag string) int {
	if c, ok := h.counter.Load(tag); ok {
		return c.(*counter.TrafficCounter).Len()
	}
	return 0
}

type HookServer struct {
	logger  log.Logger
	counter sync.Map
}

func (h *HookServer) ModeList() []string {
	return nil
}

func NewHookServer(logger log.Logger) *HookServer {
	return &HookServer{
		logger:  logger,
		counter: sync.Map{},
	}
}

func (h *HookServer) Start() error {
	return nil
}

func (h *HookServer) Close() error {
	return nil
}

func (h *HookServer) PreStart() error {
	return nil
}

func (h *HookServer) RoutedConnection(_ context.Context, conn net.Conn, m adapter.InboundContext, _ adapter.Rule) (net.Conn, adapter.Tracker) {
	t := &Tracker{tag: m.Inbound, user: m.User}
	l, err := limiter.GetLimiter(m.Inbound)
	if err != nil {
		log.Error("get limiter for ", m.Inbound, " error: ", err)
	}
	if l.CheckDomainRule(m.Domain) {
		conn.Close()
		h.logger.Error("[", m.Inbound, "] ",
			"Limited ", m.User, " access to ", m.Domain, " by domain rule")
		return conn, t
	}
	if l.CheckProtocolRule(m.Protocol) {
		conn.Close()
		h.logger.Error("[", m.Inbound, "] ",
			"Limited ", m.User, " use ", m.Domain, " by protocol rule")
		return conn, t
	}
	ip := m.Source.Addr.String()
	if b, r := l.CheckLimit(m.User, ip, true); r {
		conn.Close()
		h.logger.Error("[", m.Inbound, "] ", "Limited ", m.User, " by ip or conn")
		return conn, t
	} else if b != nil {
		conn = rate.NewConnRateLimiter(conn, b)
	}
	t.l = func() {
		l.ConnLimiter.DelConnCount(m.User, ip)
	}
	if c, ok := h.counter.Load(m.Inbound); ok {
		return counter.NewConnCounter(conn, c.(*counter.TrafficCounter).GetCounter(m.User)), t
	} else {
		c := counter.NewTrafficCounter()
		h.counter.Store(m.Inbound, c)
		return counter.NewConnCounter(conn, c.GetCounter(m.User)), t
	}
}

func (h *HookServer) RoutedPacketConnection(_ context.Context, conn N.PacketConn, m adapter.InboundContext, _ adapter.Rule) (N.PacketConn, adapter.Tracker) {
	t := &Tracker{tag: m.Inbound, user: m.User}
	l, err := limiter.GetLimiter(m.Inbound)
	if err != nil {
		log.Error("get limiter for ", m.Inbound, " error: ", err)
	}
	if l.CheckDomainRule(m.Domain) {
		conn.Close()
		h.logger.Error("[", m.Inbound, "] ",
			"Limited ", m.User, " access to ", m.Domain, " by domain rule")
		return conn, t
	}
	if l.CheckProtocolRule(m.Protocol) {
		conn.Close()
		h.logger.Error("[", m.Inbound, "] ",
			"Limited ", m.User, " use ", m.Domain, " by protocol rule")
		return conn, t
	}
	ip := m.Source.Addr.String()
	if b, r := l.CheckLimit(m.User, ip, true); r {
		conn.Close()
		h.logger.Error("[", m.Inbound, "] ", "Limited ", m.User, " by ip or conn")
		return conn, &Tracker{}
	} else if b != nil {
		conn = rate.NewPacketConnCounter(conn, b)
	}
	if c, ok := h.counter.Load(m.Inbound); ok {
		return counter.NewPacketConnCounter(conn, c.(*counter.TrafficCounter).GetCounter(m.User)), t
	} else {
		c := counter.NewTrafficCounter()
		h.counter.Store(m.Inbound, c)
		return counter.NewPacketConnCounter(conn, c.GetCounter(m.User)), t
	}
}

// not need

func (h *HookServer) Mode() string {
	return ""
}
func (h *HookServer) StoreSelected() bool {
	return false
}
func (h *HookServer) CacheFile() adapter.ClashCacheFile {
	return nil
}
func (h *HookServer) HistoryStorage() *urltest.HistoryStorage {
	return nil
}

func (h *HookServer) StoreFakeIP() bool {
	return false
}

type Tracker struct {
	l   func()
	tag  string
	user string
}

func (t *Tracker) Leave() {
	if t.tag != "" && t.user != "" {
		// Pull final traffic from counter and expose to Prometheus
		if c := globalHookServer.GetCounter(t.tag); c != nil {
			up := c.GetUpCount(t.user)
			down := c.GetDownCount(t.user)
			ExposeHookMetrics(t.tag, up, down, -1)
		}
	}
	t.l()
}

// globalHookServer holds the Box-level hookServer for Tracker.Leave() access.
// Set by Box creation.
var globalHookServer *HookServer

func setGlobalHookServer(h *HookServer) {
	globalHookServer = h
}
