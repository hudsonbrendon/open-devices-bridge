package hapublish

import (
	"encoding/json"
	"testing"

	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
)

func decode(t *testing.T, s string) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal([]byte(s), &m); err != nil {
		t.Fatalf("bad json: %v", err)
	}
	return m
}

var prov = protocol.ProviderInfo{ID: "ble-battery", Name: "BLE Battery", Version: "1.0.0"}
var dev = protocol.Device{
	ID: "mx-keys-mini", Name: "MX Keys Mini", Manufacturer: "Logitech", Model: "MX Keys Mini",
	Entities: []protocol.Entity{
		{Key: "battery", Kind: "sensor", DeviceClass: "battery", Unit: "%"},
		{Key: "connected", Kind: "binary_sensor", DeviceClass: "connectivity"},
		{Key: "firmware", Kind: "sensor", EntityCategory: "diagnostic"},
	},
}

func TestSlug(t *testing.T) {
	cases := map[string]string{"MX Keys Mini": "mx_keys_mini", "ble-battery": "ble_battery", "!!!": "device"}
	for in, want := range cases {
		if got := Slug(in); got != want {
			t.Errorf("Slug(%q)=%q want %q", in, got, want)
		}
	}
}

func TestObjectID(t *testing.T) {
	if got := ObjectID("ble-battery", "mx-keys-mini"); got != "ble_battery_mx_keys_mini" {
		t.Fatalf("ObjectID=%q", got)
	}
}

func TestStateTopicAndMessage(t *testing.T) {
	if got := StateTopic("ble-battery", "mx-keys-mini"); got != "odb/ble_battery/mx_keys_mini/state" {
		t.Fatalf("StateTopic=%q", got)
	}
	out := StateMessage("ble-battery", dev, map[string]any{"battery": 55, "connected": true})
	if out.Topic != "odb/ble_battery/mx_keys_mini/state" || !out.Retained {
		t.Fatalf("bad state msg: %+v", out)
	}
	body := decode(t, out.Payload)
	if body["battery"].(float64) != 55 || body["connected"].(bool) != true {
		t.Fatalf("bad state body: %v", body)
	}
}

func TestDiscoveryMessages(t *testing.T) {
	msgs := DiscoveryMessages(prov, dev)
	if len(msgs) != 3 {
		t.Fatalf("want 3 configs, got %d", len(msgs))
	}
	var battery *OutMessage
	for i := range msgs {
		if !msgs[i].Retained {
			t.Fatalf("config not retained: %+v", msgs[i])
		}
		if msgs[i].Topic == "homeassistant/sensor/odb_ble_battery_mx_keys_mini/battery/config" {
			battery = &msgs[i]
		}
	}
	if battery == nil {
		t.Fatal("battery config topic missing")
	}
	p := decode(t, battery.Payload)
	if p["unique_id"] != "odb_ble_battery_mx_keys_mini_battery" {
		t.Errorf("unique_id=%v", p["unique_id"])
	}
	if p["device_class"] != "battery" || p["unit_of_measurement"] != "%" {
		t.Errorf("battery attrs wrong: %v", p)
	}
	if p["state_topic"] != "odb/ble_battery/mx_keys_mini/state" {
		t.Errorf("state_topic=%v", p["state_topic"])
	}
	if p["value_template"] != "{{ value_json.battery }}" {
		t.Errorf("value_template=%v", p["value_template"])
	}
	d := p["device"].(map[string]any)
	if d["name"] != "MX Keys Mini" {
		t.Errorf("device.name=%v", d["name"])
	}
}

func TestBinarySensorTemplate(t *testing.T) {
	msgs := DiscoveryMessages(prov, dev)
	for _, m := range msgs {
		if m.Topic == "homeassistant/binary_sensor/odb_ble_battery_mx_keys_mini/connected/config" {
			p := decode(t, m.Payload)
			if p["value_template"] != "{{ 'ON' if value_json.connected else 'OFF' }}" {
				t.Fatalf("binary template=%v", p["value_template"])
			}
			if p["payload_on"] != "ON" || p["payload_off"] != "OFF" {
				t.Fatalf("payloads wrong: %v", p)
			}
			return
		}
	}
	t.Fatal("connected binary_sensor config missing")
}

func TestUnknownKindSkipped(t *testing.T) {
	d := protocol.Device{ID: "x", Name: "X", Entities: []protocol.Entity{
		{Key: "press", Kind: "button"},
		{Key: "level", Kind: "sensor"},
	}}
	msgs := DiscoveryMessages(prov, d)
	if len(msgs) != 1 {
		t.Fatalf("control kind should be skipped; got %d msgs", len(msgs))
	}
}
