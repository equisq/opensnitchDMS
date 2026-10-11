package main

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// AppInfo is what the prompt shows about the process: a friendly name and icon
// taken from its .desktop entry, like the Qt UI's LinuxDesktopParser.
type AppInfo struct {
	Name        string `json:"name"`
	Icon        string `json:"icon"`
	Description string `json:"description"`
}

var (
	desktopOnce sync.Once
	desktopByEx map[string]AppInfo
)

func scanDesktop() {
	desktopByEx = map[string]AppInfo{}
	dirs := []string{"/usr/share/applications", "/usr/local/share/applications", "/var/lib/flatpak/exports/share/applications"}
	if home, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, filepath.Join(home, ".local/share/applications"),
			filepath.Join(home, ".local/share/flatpak/exports/share/applications"))
	}
	for _, d := range dirs {
		files, _ := filepath.Glob(filepath.Join(d, "*.desktop"))
		for _, f := range files {
			fh, err := os.Open(f)
			if err != nil {
				continue
			}
			var info AppInfo
			var exec string
			inEntry := false
			sc := bufio.NewScanner(fh)
			for sc.Scan() {
				l := strings.TrimSpace(sc.Text())
				if strings.HasPrefix(l, "[") {
					inEntry = l == "[Desktop Entry]"
					continue
				}
				if !inEntry {
					continue
				}
				k, v, ok := strings.Cut(l, "=")
				if !ok {
					continue
				}
				switch k {
				case "Name":
					info.Name = v
				case "Comment":
					info.Description = v
				case "Icon":
					info.Icon = v
				case "Exec":
					if exec == "" {
						exec = v
					}
				}
			}
			fh.Close()
			fields := strings.Fields(exec)
			// skip wrappers: env VAR=x prog
			for len(fields) > 0 && (fields[0] == "env" || strings.Contains(fields[0], "=")) {
				fields = fields[1:]
			}
			if len(fields) == 0 || info.Name == "" {
				continue
			}
			base := filepath.Base(fields[0])
			if _, dup := desktopByEx[base]; !dup {
				desktopByEx[base] = info
			}
		}
	}
}

func appInfoFor(processPath string) AppInfo {
	desktopOnce.Do(scanDesktop)
	base := filepath.Base(processPath)
	if i, ok := desktopByEx[base]; ok {
		return i
	}
	return AppInfo{Name: base}
}
