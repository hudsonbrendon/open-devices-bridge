package config

import (
	"path/filepath"
	"testing"
)

func TestSaveLoadRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	in := Settings{Host: "192.168.31.150", Port: 1883, Username: "ha", IntervalMinutes: 5}
	if err := saveTo(path, in); err != nil {
		t.Fatalf("save: %v", err)
	}
	out, err := loadFrom(path)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if out != in {
		t.Fatalf("round trip mismatch: %+v vs %+v", out, in)
	}
}

func TestLoadMissingReturnsDefaults(t *testing.T) {
	out, err := loadFrom(filepath.Join(t.TempDir(), "nope.json"))
	if err != nil {
		t.Fatalf("expected defaults, got error: %v", err)
	}
	if out.Port != 1883 || out.IntervalMinutes != 5 {
		t.Fatalf("bad defaults: %+v", out)
	}
}
