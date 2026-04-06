package logger

import (
	"log/slog"
	"os"
	"path/filepath"
)

var std *slog.Logger

func Init(path, level string) {
	os.MkdirAll(filepath.Dir(path), 0755)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		std = slog.New(slog.NewJSONHandler(os.Stderr, nil))
		return
	}
	h := slog.NewJSONHandler(f, nil)
	std = slog.New(h)
	slog.SetDefault(std)
}

func Info(msg string, args ...any) { std.Info(msg, args...) }
func Warn(msg string, args ...any) { std.Warn(msg, args...) }
func Error(msg string, args ...any) { std.Error(msg, args...) }
func Debug(msg string, args ...any) { std.Debug(msg, args...) }
