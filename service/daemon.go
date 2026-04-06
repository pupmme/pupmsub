package service

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/pupmme/pupmsub/db"
	"github.com/pupmme/pupmsub/logger"
	"github.com/pupmme/pupmsub/network"
)

var daemon *XboardDaemon

func GetDaemon() *XboardDaemon { return daemon }

type XboardDaemon struct {
	mu          sync.RWMutex
	ctx, cancel context.CancelFunc
	wg          sync.WaitGroup

	syncMu      sync.Mutex
	connected   bool
	connMu      sync.RWMutex
	lastSync    time.Time
	lastReport  time.Time

	snapMu          sync.RWMutex
	lastTrafficSnap map[int64][2]int64

	hc *network.Client
}

func InitDaemon() {
	daemon = &XboardDaemon{
		lastTrafficSnap: make(map[int64][2]int64),
		hc:              network.NewClient(),
	}
}

func (d *XboardDaemon) Start(ctx context.Context) {
	d.mu.Lock()
	d.ctx, d.cancel = context.WithCancel(ctx)
	d.mu.Unlock()

	logger.Info("[daemon] starting...")
	if err := d.doHandshake(); err != nil {
		logger.Warn("[daemon] initial handshake failed: ", err)
	}

	d.wg.Add(1)
	go d.syncLoop()
	d.wg.Add(1)
	go d.reportLoop()
	d.wg.Add(1)
	go d.statusLoop()
}

// ForceSync triggers an immediate xboard sync (used by API).
func (d *XboardDaemon) ForceSync() {
	if !d.IsConnected() {
		_ = d.doHandshake()
		return
	}
	_ = d.doSync()
}

func (d *XboardDaemon) Stop() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cancel != nil {
		d.cancel()
	}
	d.wg.Wait()
	logger.Info("[daemon] stopped")
}

func (d *XboardDaemon) IsConnected() bool {
	d.connMu.RLock()
	defer d.connMu.RUnlock()
	return d.connected
}

func (d *XboardDaemon) GetStatus() map[string]any {
	d.syncMu.Lock()
	defer d.syncMu.Unlock()
	inf := GetSingbox()
	return map[string]any{
		"connected":      d.IsConnected(),
		"singbox_running": inf != nil && inf.IsRunning(),
		"last_sync":      d.lastSync.Format(time.RFC3339),
		"last_report":    d.lastReport.Format(time.RFC3339),
		"pid":            func() int { if inf != nil { return inf.PID() }; return 0 }(),
	}
}

// ---- handshake ----

func (d *XboardDaemon) doHandshake() error {
	for attempt := 1; attempt <= 3; attempt++ {
		hs, err := d.hc.Handshake("pupmsub/1.0.0")
		if err == nil {
			d.setConnected(true)
			logger.Info("[daemon] handshake ok, xboard: ", hs.Version)

			// Load traffic baseline from persisted snap
			d.snapMu.Lock()
			d.lastTrafficSnap = db.GetTrafficSnap()
			if len(d.lastTrafficSnap) > 0 {
				logger.Info("[daemon] traffic baseline loaded, users=", len(d.lastTrafficSnap))
			}
			d.snapMu.Unlock()

			// Sync inbound + users
			if hs.Config != nil {
				ib := networkNodeConfigToInbound(hs.Config)
				db.SetInboundsBasic([]InboundBasic{{
					Tag:  hs.Config.Tag,
					Type: hs.Config.Type,
					Port: hs.Config.Port,
					Listen: "0.0.0.0",
					XboardTag: hs.Config.Tag,
				}})
				_ = d.applyConfig()
			}
			if len(hs.Users) > 0 {
				users := make([]User, len(hs.Users))
				for i, u := range hs.Users {
					users[i] = User(u)
				}
				db.SetTrafficSnap(buildSnapFromUsers(users))
				_ = d.applyConfig()
			}

			GetSingbox().Restart()
			return nil
		}
		logger.Warn(fmt.Sprintf("[daemon] handshake attempt %d failed: %v", attempt, err))
		if attempt < 3 {
			time.Sleep(time.Duration(attempt*5) * time.Second)
		}
	}
	// Clear stale etag cache so next syncLoop retry doesn't get stuck on 304
	d.hc.ResetETags()
	d.setConnected(false)
	return fmt.Errorf("all handshake attempts failed")
}

func networkNodeConfigToInbound(nc *network.NodeConfig) db.InboundBasic {
	ib := db.InboundBasic{
		Tag:     nc.Tag,
		Type:    nc.Type,
		Port:    nc.Port,
		Listen:  "0.0.0.0",
	}
	if nc.Settings != nil {
		if v, ok := nc.Settings["uuid"].(string); ok { ib.UUID = v }
		if v, ok := nc.Settings["password"].(string); ok { ib.Password = v }
	}
	return ib
}

func buildSnapFromUsers(users []User) map[int64][2]int64 {
	snap := make(map[int64][2]int64)
	for _, u := range users {
		snap[u.ID] = [2]int64{u.Up, u.Down}
	}
	return snap
}

func (d *XboardDaemon) setConnected(v bool) {
	d.connMu.Lock()
	defer d.connMu.Unlock()
	d.connected = v
}

// ---- syncLoop ----

func (d *XboardDaemon) syncLoop() {
	defer d.wg.Done()
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-d.ctx.Done():
			return
		case <-ticker.C:
			if !d.IsConnected() {
				_ = d.doHandshake()
				continue
			}
			_ = d.doSync()
		}
	}
}

func (d *XboardDaemon) doSync() error {
	cfg, err := d.hc.GetConfig()
	if err != nil {
		logger.Warn("[daemon] get config: ", err)
		return err
	}
	if cfg == nil {
		// 304 Not Modified — skip
		return nil
	}

	ibs := db.GetInboundsBasic()
	for i := range ibs {
		if ibs[i].Tag == cfg.Tag || ibs[i].XboardTag == cfg.Tag {
			ibs[i].Type = cfg.Type
			ibs[i].Port = cfg.Port
			if cfg.Settings != nil {
				if v, ok := cfg.Settings["uuid"].(string); ok { ibs[i].UUID = v }
				if v, ok := cfg.Settings["password"].(string); ok { ibs[i].Password = v }
			}
		}
	}
	db.SetInboundsBasic(ibs)

	users, err := d.hc.GetUsers()
	if err != nil {
		logger.Warn("[daemon] get users: ", err)
	} else if len(users) > 0 {
		dbRules := make([]User, len(users))
		for i, u := range users {
			dbRules[i] = User(u)
		}
		db.SetTrafficSnap(buildSnapFromUsers(dbRules))
	}

	if err := d.applyConfig(); err != nil {
		return err
	}
	GetSingbox().Restart()

	d.syncMu.Lock()
	d.lastSync = time.Now()
	d.syncMu.Unlock()
	logger.Info("[daemon] sync done")
	return nil
}

func (d *XboardDaemon) applyConfig() error {
	ibs := db.GetInboundsBasic()
	var mainIB *db.InboundBasic
	for i := range ibs {
		if ibs[i].XboardTag != "" {
			mainIB = &ibs[i]
			break
		}
	}
	cfg := GenerateSingboxConfig(mainIB)
	return GetSingbox().WriteConfig(cfg)
}

// ---- reportLoop ----

func (d *XboardDaemon) reportLoop() {
	defer d.wg.Done()
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-d.ctx.Done():
			return
		case <-ticker.C:
			if !d.IsConnected() {
				continue
			}
			d.pushTraffic()
		}
	}
}

func (d *XboardDaemon) pushTraffic() {
	snap := db.GetTrafficSnap()

	d.snapMu.Lock()
	delta := make(map[int64][2]int64)
	for id, cur := range snap {
		last, ok := d.lastTrafficSnap[id]
		if ok {
			delta[id] = [2]int64{cur[0] - last[0], cur[1] - last[1]}
		} else {
			delta[id] = [2]int64{0, 0}
		}
		d.lastTrafficSnap[id] = cur
	}
	db.SetTrafficSnap(d.lastTrafficSnap)
	d.snapMu.Unlock()

	for id, dlt := range delta {
		req := network.TrafficRequest{NodeID: 1, UserID: id, U: dlt[0], D: dlt[1]}
		if err := d.hc.ReportTraffic([]network.TrafficRequest{req}); err != nil {
			logger.Debug("[daemon] report traffic: ", err)
		}
	}
	d.syncMu.Lock()
	d.lastReport = time.Now()
	d.syncMu.Unlock()
}

// ---- statusLoop ----

func (d *XboardDaemon) statusLoop() {
	defer d.wg.Done()
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-d.ctx.Done():
			return
		case <-ticker.C:
			if !d.IsConnected() {
				continue
			}
			d.pushStatus()
		}
	}
}

func (d *XboardDaemon) pushStatus() {
	req := collectSystemStatus()
	if err := d.hc.PushStatus(req); err != nil {
		logger.Debug("[daemon] push status: ", err)
	}
}

func collectSystemStatus() *network.StatusRequest {
	req := &network.StatusRequest{}
	req.CPU, _ = getCPU()
	req.Mem, _ = getMem()
	req.Disk, _ = getDisk()
	req.Uptime = getUptime()
	req.Load = getLoad()
	return req
}
