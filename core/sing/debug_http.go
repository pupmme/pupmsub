package sing

import (
	"net/http"
	"net/http/pprof"
	"runtime"
	"runtime/debug"

	"github.com/inazumav/sing-box/common/badjson"
	"github.com/inazumav/sing-box/common/json"
	"github.com/inazumav/sing-box/log"
	"github.com/inazumav/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"

	"github.com/dustin/go-humanize"
	"github.com/go-chi/chi/v5"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	debugHTTPServer *http.Server

	// Metrics collectors
	nodeOnlineUsers = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: "v2bx",
		Name:      "online_users",
		Help:      "Number of online users per node",
	}, []string{"node_tag"})

	nodeTrafficUp = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "v2bx",
		Name:      "traffic_up_bytes",
		Help:      "Total upload traffic per node in bytes",
	}, []string{"node_tag"})

	nodeTrafficDown = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "v2bx",
		Name:      "traffic_down_bytes",
		Help:      "Total download traffic per node in bytes",
	}, []string{"node_tag"})

	nodeTrafficTotal = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: "v2bx",
		Name:      "traffic_total_bytes",
		Help:      "Current total traffic (up+down) per node in bytes",
	}, []string{"node_tag"})

	nodeConnections = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: "v2bx",
		Name:      "connections_active",
		Help:      "Number of active connections per node",
	}, []string{"node_tag"})
)

func init() {
	prometheus.MustRegister(nodeOnlineUsers)
	prometheus.MustRegister(nodeTrafficUp)
	prometheus.MustRegister(nodeTrafficDown)
	prometheus.MustRegister(nodeTrafficTotal)
	prometheus.MustRegister(nodeConnections)
}

// ExposeHookMetrics lets hook.go push traffic/counter data for Prometheus scraping.
func ExposeHookMetrics(tag string, upBytes, downBytes int64, onlineConns int) {
	nodeTrafficUp.WithLabelValues(tag).Add(float64(upBytes))
	nodeTrafficDown.WithLabelValues(tag).Add(float64(downBytes))
	nodeTrafficTotal.WithLabelValues(tag).Set(float64(upBytes + downBytes))
	nodeConnections.WithLabelValues(tag).Set(float64(onlineConns))
}

// SetOnlineUsers sets the online user gauge for a node.
func SetOnlineUsers(tag string, count int) {
	nodeOnlineUsers.WithLabelValues(tag).Set(float64(count))
}

func applyDebugListenOption(options option.DebugOptions) {
	if debugHTTPServer != nil {
		debugHTTPServer.Close()
		debugHTTPServer = nil
	}
	if options.Listen == "" {
		return
	}
	r := chi.NewMux()
	r.Route("/debug", func(r chi.Router) {
		r.Get("/gc", func(writer http.ResponseWriter, request *http.Request) {
			writer.WriteHeader(http.StatusNoContent)
			go debug.FreeOSMemory()
		})
		r.Get("/memory", func(writer http.ResponseWriter, request *http.Request) {
			var memStats runtime.MemStats
			runtime.ReadMemStats(&memStats)

			var memObject badjson.JSONObject
			memObject.Put("heap", humanize.IBytes(memStats.HeapInuse))
			memObject.Put("stack", humanize.IBytes(memStats.StackInuse))
			memObject.Put("idle", humanize.IBytes(memStats.HeapIdle-memStats.HeapReleased))
			memObject.Put("goroutines", runtime.NumGoroutine())
			memObject.Put("rss", rusageMaxRSS())

			encoder := json.NewEncoder(writer)
			encoder.SetIndent("", "  ")
			encoder.Encode(memObject)
		})
		r.HandleFunc("/pprof", pprof.Index)
		r.HandleFunc("/pprof/*", pprof.Index)
		r.HandleFunc("/pprof/cmdline", pprof.Cmdline)
		r.HandleFunc("/pprof/profile", pprof.Profile)
		r.HandleFunc("/pprof/symbol", pprof.Symbol)
		r.HandleFunc("/pprof/trace", pprof.Trace)
	})
	// Prometheus /metrics endpoint
	r.Handle("/metrics", promhttp.Handler())
	debugHTTPServer = &http.Server{
		Addr:    options.Listen,
		Handler: r,
	}
	go func() {
		err := debugHTTPServer.ListenAndServe()
		if err != nil && !E.IsClosed(err) {
			log.Error(E.Cause(err, "serve debug HTTP server"))
		}
	}()
}
