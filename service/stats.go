package service

import (
	"runtime"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/mem"
)

func getCPU() (float64, error) {
	p, err := cpu.Percent(0, false)
	if err != nil || len(p) == 0 {
		return 0, err
	}
	return p[0], nil
}

func getMem() ([2]uint64, error) {
	m, err := mem.VirtualMemory()
	if err != nil {
		return [2]uint64{}, err
	}
	return [2]uint64{m.Total, m.Used}, nil
}

func getDisk() ([2]uint64, error) {
	parts, err := disk.Partitions(false)
	if err != nil {
		return [2]uint64{}, err
	}
	for _, p := range parts {
		if p.Mountpoint == "/" || p.Mountpoint == "" {
			u, err := disk.Usage(p.Mountpoint)
			if err != nil {
				continue
			}
			return [2]uint64{u.Total, u.Used}, nil
		}
	}
	return [2]uint64{}, nil
}

func getUptime() int64 {
	bootTime := time.Now().Unix() - int64(runtime.Uptime())
	return bootTime
}

func getLoad() [3]float64 {
	load, err := cpu.LoadAvg()
	if err != nil {
		return [3]float64{}
	}
	return [3]float64{load.Load1, load.Load5, load.Load15}
}
