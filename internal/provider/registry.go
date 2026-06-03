package provider

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Manifest is the provider.json describing how to launch a provider.
type Manifest struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Exec      string   `json:"exec"`
	Args      []string `json:"args"`
	Platforms []string `json:"platforms"`
	Enabled   bool     `json:"enabled"`

	Dir string `json:"-"` // absolute provider directory, filled by Discover
}

// Command returns the executable and args to launch this provider. A ".py"
// exec is run via python3; anything else is executed directly from Dir.
func (m Manifest) Command() (string, []string) {
	if strings.HasSuffix(m.Exec, ".py") {
		return "python3", append([]string{filepath.Join(m.Dir, m.Exec)}, m.Args...)
	}
	return filepath.Join(m.Dir, m.Exec), m.Args
}

// Discover scans each root for `<root>/<id>/provider.json`, returning the
// enabled manifests that support the current OS.
func Discover(roots []string) []Manifest {
	var out []Manifest
	for _, root := range roots {
		entries, err := os.ReadDir(root)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			dir := filepath.Join(root, e.Name())
			data, err := os.ReadFile(filepath.Join(dir, "provider.json"))
			if err != nil {
				continue
			}
			var m Manifest
			if err := json.Unmarshal(data, &m); err != nil {
				continue
			}
			m.Dir = dir
			if !m.Enabled || !supportsOS(m.Platforms) {
				continue
			}
			out = append(out, m)
		}
	}
	return out
}

func supportsOS(platforms []string) bool {
	for _, p := range platforms {
		if p == runtime.GOOS {
			return true
		}
	}
	return false
}
