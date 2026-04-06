package cmd

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/pupmme/pupmsub/api"
	"github.com/pupmme/pupmsub/config"
	"github.com/pupmme/pupmsub/db"
	"github.com/pupmme/pupmsub/logger"
	"github.com/pupmme/pupmsub/service"
	"github.com/spf13/cobra"
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Start pupmsub daemon",
	RunE:  runDaemon,
}

func runDaemon(cmd *cobra.Command, args []string) error {
	cfgPath := os.Getenv("PUPMUB_CONFIG")
	if cfgPath == "" {
		cfgPath = config.DefaultConfigPath()
	}

	if err := config.Load(cfgPath); err != nil {
		return err
	}
	cfg := config.Get()

	logger.Init(cfg.LogPath, cfg.LogLevel)
	logger.Info("pupmsub starting...")

	// Init data directories
	db.Init(cfg.DataDir)

	// Init sing-box service
	service.InitSingbox()

	// Init daemon
	service.InitDaemon()

	// Start HTTP API server
	go api.RunServer()
	logger.Info("HTTP server listening on :", cfg.WebPort)

	// Start daemon (handshake + loops)
	ctx, cancel := context.WithCancel(context.Background())
	service.GetDaemon().Start(ctx)

	// Graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh
	logger.Info("shutting down...")
	cancel()
	service.GetDaemon().Stop()
	service.GetSingbox().Stop()
	return nil
}
