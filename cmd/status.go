package cmd

import (
	"fmt"

	"github.com/pupmme/pupmsub/config"
	"github.com/pupmme/pupmsub/service"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Print node status",
	Run: func(cmd *cobra.Command, args []string) {
		cfg := config.Get()
		daemon := service.GetDaemon()
		if daemon == nil {
			fmt.Println("daemon not running")
			return
		}
		st := daemon.GetStatus()
		fmt.Printf("Node ID:    %d\n", cfg.NodeID)
		fmt.Printf("xboard:     %s\n", st["connected"].(bool))
		fmt.Printf("sing-box:   %s\n", st["singbox_running"].(bool))
		fmt.Printf("Last sync:  %s\n", st["last_sync"])
		fmt.Printf("Last report:%s\n", st["last_report"])
		fmt.Printf("API host:   %s\n", cfg.APIHost)
	},
}
