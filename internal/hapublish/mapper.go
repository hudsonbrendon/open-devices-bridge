// Package hapublish maps provider devices to Home Assistant MQTT Discovery
// configs and state messages, and publishes them over MQTT.
package hapublish

import (
	"encoding/json"
	"fmt"
	"strings"
	"unicode"

	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
)

// BridgeAvailabilityTopic is the host-level availability topic (also the LWT).
const BridgeAvailabilityTopic = "odb/bridge/availability"

const (
	Available   = "online"
	Unavailable = "offline"
)

// OutMessage is one MQTT message to publish.
type OutMessage struct {
	Topic    string
	Payload  string
	Retained bool
}

// Slug normalizes a string to lowercase alphanumeric+underscore.
func Slug(s string) string {
	var b strings.Builder
	lastUnderscore := false
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
			lastUnderscore = false
		} else if !lastUnderscore {
			b.WriteByte('_')
			lastUnderscore = true
		}
	}
	out := strings.Trim(b.String(), "_")
	if out == "" {
		return "device"
	}
	return out
}

// ObjectID is the stable id for a device: <provider>_<device>.
func ObjectID(providerID, deviceID string) string {
	return Slug(providerID) + "_" + Slug(deviceID)
}

// StateTopic is where a device's live values are published.
func StateTopic(providerID, deviceID string) string {
	return fmt.Sprintf("odb/%s/%s/state", Slug(providerID), Slug(deviceID))
}

// supportedComponent returns the HA component for a kind, or "" if unsupported
// in SP1 (control kinds are declared but not yet wired).
func supportedComponent(kind string) string {
	switch kind {
	case "sensor":
		return "sensor"
	case "binary_sensor":
		return "binary_sensor"
	default:
		return ""
	}
}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

// StateMessage builds the retained state payload for a device.
func StateMessage(providerID string, d protocol.Device, values map[string]any) OutMessage {
	return OutMessage{
		Topic:    StateTopic(providerID, d.ID),
		Payload:  mustJSON(values),
		Retained: true,
	}
}

// DiscoveryMessages builds one retained HA discovery config per supported entity.
func DiscoveryMessages(p protocol.ProviderInfo, d protocol.Device) []OutMessage {
	obj := ObjectID(p.ID, d.ID)
	state := StateTopic(p.ID, d.ID)
	device := map[string]any{
		"identifiers":  []string{"odb_" + obj},
		"name":         d.Name,
		"manufacturer": orDefault(d.Manufacturer, p.Name),
		"model":        orDefault(d.Model, d.Name),
	}

	var out []OutMessage
	for _, e := range d.Entities {
		component := supportedComponent(e.Kind)
		if component == "" {
			continue
		}
		payload := map[string]any{
			"unique_id":             "odb_" + obj + "_" + e.Key,
			"object_id":             obj + "_" + e.Key,
			"name":                  titleize(e.Key),
			"state_topic":           state,
			"availability_topic":    BridgeAvailabilityTopic,
			"payload_available":     Available,
			"payload_not_available": Unavailable,
			"device":                device,
		}
		if e.DeviceClass != "" {
			payload["device_class"] = e.DeviceClass
		}
		if e.EntityCategory != "" {
			payload["entity_category"] = e.EntityCategory
		}
		switch e.Kind {
		case "sensor":
			payload["value_template"] = fmt.Sprintf("{{ value_json.%s }}", e.Key)
			if e.Unit != "" {
				payload["unit_of_measurement"] = e.Unit
			}
		case "binary_sensor":
			payload["value_template"] = fmt.Sprintf("{{ 'ON' if value_json.%s else 'OFF' }}", e.Key)
			payload["payload_on"] = "ON"
			payload["payload_off"] = "OFF"
		}
		topic := fmt.Sprintf("homeassistant/%s/odb_%s/%s/config", component, obj, e.Key)
		out = append(out, OutMessage{Topic: topic, Payload: mustJSON(payload), Retained: true})
	}
	return out
}

func orDefault(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

func titleize(key string) string {
	parts := strings.Split(key, "_")
	for i, p := range parts {
		if p == "" {
			continue
		}
		parts[i] = strings.ToUpper(p[:1]) + p[1:]
	}
	return strings.Join(parts, " ")
}
