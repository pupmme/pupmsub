package logger

import (
	"os"
	"path/filepath"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

var log *zap.Logger

// Init creates a high-performance zap logger with sync.Pool buffering.
// Avoids reflection and heap allocation on every log call.
func Init(path, level string) {
	os.MkdirAll(filepath.Dir(path), 0755)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		f = os.Stderr
	}

	var zapLevel zapcore.Level
	switch level {
	case "debug":
		zapLevel = zapcore.DebugLevel
	case "warn":
		zapLevel = zapcore.WarnLevel
	case "error":
		zapLevel = zapcore.ErrorLevel
	default:
		zapLevel = zapcore.InfoLevel
	}

	encoder := zapcore.NewJSONEncoder(zapcore.EncoderConfig{
		TimeKey:        "ts",
		LevelKey:       "level",
		NameKey:        "logger",
		CallerKey:      "caller",
		MessageKey:     "msg",
		StacktraceKey:  "stack",
		LineEnding:     zapcore.DefaultLineEnding,
		EncodeLevel:    zapcore.LowercaseLevelEncoder,
		EncodeTime:     zapcore.ISO8601TimeEncoder,
		EncodeDuration: zapcore.MillisDurationEncoder,
		EncodeCaller:   zapcore.ShortCallerEncoder,
	})

	ws := zapcore.AddSync(f)
	core := zapcore.NewCore(encoder, ws, zapLevel)
	log = zap.New(core, zap.AddCaller(), zap.AddCallerSkip(1))
	zap.RedirectStdLog(log)
}

func Info(msg string, fields ...zap.Field) {
	if log == nil {
		return
	}
	log.Info(msg, fields...)
}

func Warn(msg string, fields ...zap.Field) {
	if log == nil {
		return
	}
	log.Warn(msg, fields...)
}

func Error(msg string, fields ...zap.Field) {
	if log == nil {
		return
	}
	log.Error(msg, fields...)
}

func Debug(msg string, fields ...zap.Field) {
	if log == nil {
		return
	}
	log.Debug(msg, fields...)
}

// ---- Compatibility shims for existing call sites ----

func InfoCompat(msg string, args ...any) {
	fields := make([]zap.Field, 0, len(args)/2)
	for i := 0; i < len(args)-1; i += 2 {
		if key, ok := args[i].(string); ok {
			fields = append(fields, zap.Any(key, args[i+1]))
		}
	}
	Info(msg, fields...)
}

func WarnCompat(msg string, args ...any) {
	fields := make([]zap.Field, 0, len(args)/2)
	for i := 0; i < len(args)-1; i += 2 {
		if key, ok := args[i].(string); ok {
			fields = append(fields, zap.Any(key, args[i+1]))
		}
	}
	Warn(msg, fields...)
}

func ErrorCompat(msg string, args ...any) {
	fields := make([]zap.Field, 0, len(args)/2)
	for i := 0; i < len(args)-1; i += 2 {
		if key, ok := args[i].(string); ok {
			fields = append(fields, zap.Any(key, args[i+1]))
		}
	}
	Error(msg, fields...)
}

func DebugCompat(msg string, args ...any) {
	fields := make([]zap.Field, 0, len(args)/2)
	for i := 0; i < len(args)-1; i += 2 {
		if key, ok := args[i].(string); ok {
			fields = append(fields, zap.Any(key, args[i+1]))
		}
	}
	Debug(msg, fields...)
}
