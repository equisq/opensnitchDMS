package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// Settings are the UI-side preferences (what the Qt UI keeps in its QSettings).
// Daemon-side options live in the daemon's own config and are changed through
// CHANGE_CONFIG notifications instead.
type Settings struct {
	DisablePopups        bool           `json:"disablePopups"`
	Timeout              int            `json:"timeout"`         // seconds before the default applies; 0 = at once
	DefaultAction        string         `json:"defaultAction"`   // allow | deny | reject
	DefaultDuration      string         `json:"defaultDuration"` // a durations[] id
	DefaultTarget        int            `json:"defaultTarget"`   // index into the fixed targets
	PopupAdvanced        bool           `json:"popupAdvanced"`
	AdvDstIP             bool           `json:"advDstIp"`
	AdvDstPort           bool           `json:"advDstPort"`
	AdvUID               bool           `json:"advUid"`
	AdvChecksum          bool           `json:"advChecksum"`
	StatsBaseline        map[string]any `json:"statsBaseline,omitempty"`
	StatsBaselineNodeKey string         `json:"statsBaselineNodeKey,omitempty"`
}

func defaultSettings() Settings {
	return Settings{
		Timeout:         15,
		DefaultAction:   actionDeny,
		DefaultDuration: "until restart",
		DefaultTarget:   0,
	}
}

type SettingsStore struct {
	mu   sync.Mutex
	path string
	v    Settings
}

func loadSettings(dir string) *SettingsStore {
	s := &SettingsStore{path: filepath.Join(dir, "settings.json"), v: defaultSettings()}
	if b, err := os.ReadFile(s.path); err == nil {
		_ = json.Unmarshal(b, &s.v)
	}
	s.v.normalize()
	return s
}

func (s *Settings) normalize() {
	switch s.DefaultAction {
	case actionAllow, actionDeny, actionReject:
	default:
		s.DefaultAction = actionDeny
	}
	if durationIndex(s.DefaultDuration) == 7 && s.DefaultDuration != "until restart" {
		s.DefaultDuration = "until restart"
	}
	if s.Timeout < 0 {
		s.Timeout = 0
	}
	if s.Timeout > 600 {
		s.Timeout = 600
	}
	if s.DefaultTarget < 0 || s.DefaultTarget > 5 {
		s.DefaultTarget = 0
	}
}

func (s *SettingsStore) Get() Settings {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.v
}

// Update merges a partial JSON object over the current settings.
func (s *SettingsStore) Update(patch json.RawMessage) (Settings, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := s.v
	if err := json.Unmarshal(patch, &next); err != nil {
		return s.v, err
	}
	next.normalize()
	s.v = next
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err == nil {
		b, _ := json.MarshalIndent(next, "", "  ")
		tmp := s.path + ".tmp"
		if os.WriteFile(tmp, b, 0o644) == nil {
			_ = os.Rename(tmp, s.path)
		}
	}
	return next, nil
}
