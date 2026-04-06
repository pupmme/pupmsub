package cmd

import (
	"fmt"
	"runtime"

	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version info",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("pupmsub %s\nGo: %s/%s\n",
			Version, runtime.GOOS, runtime.GOARCH)
	},
}
