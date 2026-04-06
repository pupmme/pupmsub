package cmd

import (
	"github.com/pupmme/pupmsub/config"
	"github.com/pupmme/pupmsub/service"
	"github.com/spf13/cobra"
)

var syncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Trigger xboard sync once",
	RunE:  runSync,
}

func runSync(cmd *cobra.Command, args []string) error {
	if err := config.Load(config.DefaultConfigPath()); err != nil {
		return err
	}
	service.InitDaemon()
	d := service.GetDaemon()
	if d == nil {
		println("daemon not initialized — run 'pupmsub run' first")
		return nil
	}
	if err := d.doHandshake(); err != nil {
		return err
	}
	return d.doSync()
}
