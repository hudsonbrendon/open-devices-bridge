// Package protocol defines the ODB Provider Protocol v1 (ODB-PP/1):
// newline-delimited JSON messages exchanged between the host and providers.
package protocol

import (
	"bytes"
	"encoding/json"
)

// Version is the protocol version the host speaks.
const Version = 1

// Entity is one capability of a device (maps to a HA entity).
type Entity struct {
	Key            string `json:"key"`
	Kind           string `json:"kind"`
	DeviceClass    string `json:"device_class,omitempty"`
	Unit           string `json:"unit,omitempty"`
	EntityCategory string `json:"entity_category,omitempty"`
}

// Device is a physical device exposed by a provider.
type Device struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Manufacturer string   `json:"manufacturer,omitempty"`
	Model        string   `json:"model,omitempty"`
	Entities     []Entity `json:"entities"`
}

// ProviderInfo identifies a provider (sent in the hello message).
type ProviderInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Version string `json:"version"`
}

// Message is a provider→host message. Fields are populated per Type.
type Message struct {
	Type     string         `json:"type"`
	Protocol int            `json:"protocol,omitempty"`
	Provider *ProviderInfo  `json:"provider,omitempty"`
	Devices  []Device       `json:"devices,omitempty"`
	Device   string         `json:"device,omitempty"`
	Values   map[string]any `json:"values,omitempty"`
	Online   *bool          `json:"online,omitempty"`
	Level    string         `json:"level,omitempty"`
	Message  string         `json:"message,omitempty"`
}

// Command is a host→provider message.
type Command struct {
	Type    string         `json:"type"`
	Device  string         `json:"device,omitempty"`
	Entity  string         `json:"entity,omitempty"`
	Command string         `json:"command,omitempty"`
	Payload map[string]any `json:"payload,omitempty"`
}

// DecodeLine parses one JSONL line into a Message.
func DecodeLine(line []byte) (Message, error) {
	var m Message
	dec := json.NewDecoder(bytes.NewReader(line))
	if err := dec.Decode(&m); err != nil {
		return Message{}, err
	}
	return m, nil
}

// Encode serializes a Message to a single JSON line (no trailing newline).
func (m Message) Encode() ([]byte, error) { return json.Marshal(m) }

// Encode serializes a Command to a single JSON line (no trailing newline).
func (c Command) Encode() ([]byte, error) { return json.Marshal(c) }
