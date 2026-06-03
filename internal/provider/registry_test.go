package provider

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func writeManifest(t *testing.T, dir, content string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "provider.json"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDiscoverFiltersByOS(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, "mac-only"),
		`{"id":"mac-only","name":"Mac","exec":"x","platforms":["darwin"],"enabled":true}`)
	writeManifest(t, filepath.Join(root, "linux-only"),
		`{"id":"linux-only","name":"Lin","exec":"x","platforms":["linux"],"enabled":true}`)
	writeManifest(t, filepath.Join(root, "disabled"),
		`{"id":"disabled","name":"Off","exec":"x","platforms":["darwin","linux","windows"],"enabled":false}`)

	got := Discover([]string{root})
	ids := map[string]bool{}
	for _, m := range got {
		ids[m.ID] = true
	}
	if ids["disabled"] {
		t.Error("disabled provider should be excluded")
	}
	wantMac := runtime.GOOS == "darwin"
	if ids["mac-only"] != wantMac {
		t.Errorf("mac-only present=%v want %v", ids["mac-only"], wantMac)
	}
}

func TestManifestResolvesExecPath(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "p")
	writeManifest(t, dir,
		`{"id":"p","name":"P","exec":"run.sh","platforms":["`+runtime.GOOS+`"],"enabled":true}`)
	got := Discover([]string{root})
	if len(got) != 1 {
		t.Fatalf("want 1, got %d", len(got))
	}
	if got[0].Dir != dir {
		t.Errorf("Dir=%q want %q", got[0].Dir, dir)
	}
	if got[0].Exec != "run.sh" {
		t.Errorf("Exec=%q", got[0].Exec)
	}
}
