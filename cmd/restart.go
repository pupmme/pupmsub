package cmd

import (
	"github.com/pupmme/pupmsub/config"
	"github.com/pupmme/pupmsub/service"
	"github.com/spf13/cobra"
)

var restartCmd = &cobra.Command{
	Use:   "restart",
	Short: "Restart sing-box",
	RunE:  runRestart,
}

func runRestart(cmd *cobra.Command, args []string) error {
	if err := config.Load(config.DefaultConfigPath()); err != nil {
		return err
	}
	service.InitSingbox()
	return service.GetSingbox().Restart()
}
