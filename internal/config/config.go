// Package config persists MQTT settings (file) and the password (OS keyring).
package config

import (
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/zalando/go-keyring"
)

const (
	keyringService = "online.99lab.opendevicesbridge"
	keyringAccount = "mqtt.password"
)

// Settings are the non-secret MQTT options (the password lives in the keyring).
type Settings struct {
	Host            string `json:"host"`
	Port            int    `json:"port"`
	Username        string `json:"username"`
	IntervalMinutes int    `json:"interval_minutes"`
}

func defaults() Settings { return Settings{Port: 1883, IntervalMinutes: 5} }

// Path is the OS-appropriate config file location.
func Path() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "OpenDevicesBridge", "config.json"), nil
}

func loadFrom(path string) (Settings, error) {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return defaults(), nil
	}
	if err != nil {
		return Settings{}, err
	}
	s := defaults()
	if err := json.Unmarshal(data, &s); err != nil {
		return Settings{}, err
	}
	return s, nil
}

func saveTo(path string, s Settings) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

// Load reads settings from the default path.
func Load() (Settings, error) {
	path, err := Path()
	if err != nil {
		return Settings{}, err
	}
	return loadFrom(path)
}

// Save writes settings to the default path.
func Save(s Settings) error {
	path, err := Path()
	if err != nil {
		return err
	}
	return saveTo(path, s)
}

// Password reads the stored MQTT password (empty if unset).
func Password() string {
	p, err := keyring.Get(keyringService, keyringAccount)
	if err != nil {
		return ""
	}
	return p
}

// SetPassword stores (or clears) the MQTT password in the OS keyring.
func SetPassword(p string) error {
	if p == "" {
		_ = keyring.Delete(keyringService, keyringAccount)
		return nil
	}
	return keyring.Set(keyringService, keyringAccount, p)
}
