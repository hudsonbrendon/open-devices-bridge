package app

import (
	"testing"

	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
)

func TestStoreTracksDevicesPerProvider(t *testing.T) {
	s := newStore()
	s.setDevices("ble-battery", []protocol.Device{{ID: "mx", Name: "MX"}})
	s.setDevices("host-info", []protocol.Device{{ID: "h", Name: "Host"}})
	s.setValues("ble-battery", "mx", map[string]any{"battery": 55})

	snap := s.snapshot()
	if len(snap) != 2 {
		t.Fatalf("want 2 provider groups, got %d", len(snap))
	}
	mx := s.deviceValues("ble-battery", "mx")
	if mx["battery"].(int) != 55 {
		t.Fatalf("bad values: %v", mx)
	}
}
