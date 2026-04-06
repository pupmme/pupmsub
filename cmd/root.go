package cmd

import (
	"github.com/spf13/cobra"
)

var root = &cobra.Command{
	Use:   "pupmsub",
	Short: "pupmsub — xboard node agent + sing-box manager",
}

func Execute() error {
	return root.Execute()
}

func init() {
	root.AddCommand(runCmd, syncCmd, restartCmd, statusCmd, versionCmd)
}
