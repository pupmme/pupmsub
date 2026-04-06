package service

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"github.com/pupmme/pupmsub/config"
	"github.com/pupmme/pupmsub/logger"
	"go.uber.org/zap"
)

var singbox *SingboxService

type SingboxService struct {
	mu      sync.RWMutex
	cmd     *exec.Cmd
	pid     int
	running bool
	cfgPath string
	binPath string
	oldCfg  []byte
}

func GetSingbox() *SingboxService { return singbox }

func InitSingbox() {
	singbox = &SingboxService{
		cfgPath: config.Get().SingboxConfig,
		binPath: config.Get().BinaryPath,
	}
}

func (s *SingboxService) runningState() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.running
}

func (s *SingboxService) PID() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.pid
}

func (s *SingboxService) IsRunning() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if !s.running || s.cmd == nil {
		return false
	}
	// check if process is alive
	err := s.cmd.Process.Signal(syscall.Signal(0))
	return err == nil
}

func (s *SingboxService) Start() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.running {
		_ = s.Stop()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	args := []string{"-D", "-c", s.cfgPath}
	cmd := exec.CommandContext(ctx, s.binPath, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("sing-box start: %w", err)
	}

	s.cmd = cmd
	s.pid = cmd.Process.Pid
	s.running = true

	go func() {
		err := cmd.Wait()
		s.mu.Lock()
		s.running = false
		s.mu.Unlock()
		if err != nil {
			logger.Warn("sing-box exited", zap.Error(err))
		} else {
			logger.Info("sing-box stopped gracefully")
		}
	}()

	logger.Info("sing-box started", zap.Int("pid", s.pid))
	return nil
}

func (s *SingboxService) Stop() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cmd == nil || s.cmd.Process == nil {
		return nil
	}
	// graceful: send SIGHUP first, then SIGKILL
	_ = s.cmd.Process.Signal(syscall.SIGHUP)
	time.Sleep(2 * time.Second)
	if s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
	}
	s.cmd = nil
	s.running = false
	logger.Info("sing-box stopped")
	return nil
}

func (s *SingboxService) Restart() error {
	s.mu.Lock()
	if s.oldCfg == nil {
		_ = os.ReadFile(s.cfgPath)
	}
	cfgBackup, _ := os.ReadFile(s.cfgPath)
	s.mu.Unlock()

	if err := s.Start(); err != nil {
		// rollback
		os.WriteFile(s.cfgPath, cfgBackup, 0644)
		return err
	}
	return nil
}

// WriteConfig writes sing-box config to tmp file, validates JSON, then renames.
func (s *SingboxService) WriteConfig(cfg any) error {
	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}
	// validate: try parse
	var dummy map[string]any
	if err := json.Unmarshal(b, &dummy); err != nil {
		return fmt.Errorf("invalid sing-box JSON: %w", err)
	}
	os.MkdirAll(filepath.Dir(s.cfgPath), 0755)
	tmp := s.cfgPath + ".tmp"
	if err := os.WriteFile(tmp, b, 0644); err != nil {
		return fmt.Errorf("write config: %w", err)
	}
	// backup old config before rename
	if old, err := os.ReadFile(s.cfgPath); err == nil {
		s.mu.Lock()
		s.oldCfg = old
		s.mu.Unlock()
	}
	if err := os.Rename(tmp, s.cfgPath); err != nil {
		return fmt.Errorf("rename config: %w", err)
	}
	logger.Info("sing-box config written")
	return nil
}
