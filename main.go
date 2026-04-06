package main

import (
	"os"

	"github.com/pupmme/pupmsub/cmd"
	"github.com/pupmme/pupmsub/logger"
)

func main() {
	if err := cmd.Execute(); err != nil {
		logger.Error("pupmsub: ", err)
		os.Exit(1)
	}
}
