package config

import (
	"os"
	"path/filepath"
	"sync"

	"github.com/spf13/viper"
)

var (
	cfg  *Config
	once sync.Once
)

type Config struct {
	APIHost          string `mapstructure:"api_host"`
	APIKey           string `mapstructure:"api_key"`
	NodeID           int    `mapstructure:"node_id"`
	NodeType         string `mapstructure:"node_type"`

	BinaryPath     string `mapstructure:"binary_path"`
	SingboxConfig  string `mapstructure:"singbox_config"`
	DataDir        string `mapstructure:"data_dir"`
	LogPath        string `mapstructure:"log_path"`
	LogLevel       string `mapstructure:"log_level"`
	WebPort        int    `mapstructure:"web_port"`
	Username       string `mapstructure:"username"`
	Password       string `mapstructure:"password"`

	HeartbeatInterval string `mapstructure:"heartbeat_interval"` // e.g. "30s"
	SyncInterval      string `mapstructure:"sync_interval"`       // e.g. "60s"
}

func DefaultConfigDir() string {
	if dir := os.Getenv("PUPMUB_DATA_DIR"); dir != "" {
		return dir
	}
	return "/etc/pupmsub"
}

func DefaultConfigPath() string {
	return filepath.Join(DefaultConfigDir(), "config.yaml")
}

func Load(path string) error {
	var err error
	once.Do(func() {
		dir := filepath.Dir(path)
		os.MkdirAll(dir, 0755)
		viper.SetConfigFile(path)
		viper.SetConfigType("yaml")
		if err = viper.ReadInConfig(); err != nil {
			// write defaults
			cfg = &Config{
				APIHost:     "http://localhost:8080",
				NodeID:      1,
				NodeType:    "sing-box",
				BinaryPath:  "/usr/local/bin/sing-box",
				SingboxConfig: "/etc/pupmsub/sing-box.json",
				DataDir:     DefaultConfigDir(),
				LogPath:     "/var/log/pupmsub/pupmsub.log",
				LogLevel:    "info",
				WebPort:     2053,
				Username:    "admin",
				Password:    "admin",
				HeartbeatInterval: "30s",
				SyncInterval:      "60s",
			}
			writeDefault(path)
			return
		}
		cfg = &Config{}
		err = viper.Unmarshal(cfg)
	})
	return err
}

func writeDefault(path string) {
	viper.Set("api_host", cfg.APIHost)
	viper.Set("node_id", cfg.NodeID)
	viper.Set("node_type", cfg.NodeType)
	viper.Set("binary_path", cfg.BinaryPath)
	viper.Set("singbox_config", cfg.SingboxConfig)
	viper.Set("data_dir", cfg.DataDir)
	viper.Set("log_path", cfg.LogPath)
	viper.Set("log_level", cfg.LogLevel)
	viper.Set("web_port", cfg.WebPort)
	viper.Set("username", cfg.Username)
	viper.Set("password", cfg.Password)
	viper.Set("heartbeat_interval", cfg.HeartbeatInterval)
	viper.Set("sync_interval", cfg.SyncInterval)
	viper.WriteConfig()
}

func Get() *Config { return cfg }
