# Open Devices Bridge — SP1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the macOS battery app as "Open Devices Bridge" — a Go host that launches out-of-process device providers (JSONL over stdio) and publishes their telemetry to Home Assistant via MQTT Discovery, proven with a Swift `ble-battery` provider and a Python `host-info` provider.

**Architecture:** A cross-platform Go host (`cmd/odb`) discovers and launches provider executables, each speaking the ODB Provider Protocol v1 (newline-delimited JSON). The host maps declared device entities to HA MQTT Discovery and republishes live state. Device-specific, OS-specific code lives only in providers; the existing Swift CoreBluetooth reader becomes the macOS-only `ble-battery` provider.

**Tech Stack:** Go 1.23 (host: `paho.mqtt.golang`, `fyne.io/fyne/v2`, `github.com/zalando/go-keyring`), Swift 6 (ble-battery provider), Python 3 stdlib (host-info provider), GitHub Actions on `macos-15`.

**Spec:** `docs/superpowers/specs/2026-06-03-open-devices-bridge-design.md`

---

## Conventions used by every task

- Run all Go tests with: `go test ./...` (from repo root).
- Commit messages use no co-author trailer. Author: Hudson Brendon
  `<contato.hudsonbrendon@gmail.com>`. Configure once per clone:
  ```bash
  git config user.name "Hudson Brendon"
  git config user.email "contato.hudsonbrendon@gmail.com"
  ```
- Module path: `github.com/hudsonbrendon/open-devices-bridge`.

---

## Task 0: Restructure the repo for Go + providers

**Files:**
- Create: `go.mod`
- Move: `Sources/HABatteryCore/BatteryReader.swift` → `providers/ble-battery/Sources/ble-battery/BatteryReader.swift`
- Move: `Sources/HABatteryCore/DeviceReading.swift` → `providers/ble-battery/Sources/ble-battery/DeviceReading.swift`
- Move: `spike_battery.swift`, `k3_ble_scan.py` → `reference/`
- Delete: `Sources/HABatteryCore/`, `Sources/HABatteryBridge/`, `Sources/CoreTests/`, root `Package.swift`, `Package.resolved`

- [ ] **Step 1: Create the Go module**

Run:
```bash
cd /Users/hudsonbrendon/Github/ha-battery-bridge
go mod init github.com/hudsonbrendon/open-devices-bridge
```
Expected: creates `go.mod` with `go 1.23`.

- [ ] **Step 2: Preserve the Swift reader as the seed of the provider**

```bash
mkdir -p providers/ble-battery/Sources/ble-battery reference
git mv Sources/HABatteryCore/BatteryReader.swift providers/ble-battery/Sources/ble-battery/BatteryReader.swift
git mv Sources/HABatteryCore/DeviceReading.swift providers/ble-battery/Sources/ble-battery/DeviceReading.swift
git mv spike_battery.swift reference/spike_battery.swift
git mv k3_ble_scan.py reference/k3_ble_scan.py
```

- [ ] **Step 3: Remove the old Swift host (reimplemented in Go)**

```bash
git rm -r Sources/HABatteryCore Sources/HABatteryBridge Sources/CoreTests Package.swift Package.resolved
rmdir Sources 2>/dev/null || true
```

- [ ] **Step 4: Update .gitignore for Go + Swift + build output**

Write `.gitignore`:
```
.DS_Store
.build/
build/
*.dmg
*.xcuserstate
DerivedData/
/odb
*.app
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: restructure repo for Go host + out-of-process providers"
```

---

## Task 1: Protocol package (messages + JSONL codec)

**Files:**
- Create: `internal/protocol/messages.go`
- Test: `internal/protocol/messages_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/protocol/messages_test.go`:
```go
package protocol

import "testing"

func TestDecodeHello(t *testing.T) {
	line := []byte(`{"type":"hello","protocol":1,"provider":{"id":"ble-battery","name":"BLE Battery","version":"1.0.0"}}`)
	m, err := DecodeLine(line)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if m.Type != "hello" || m.Protocol != 1 {
		t.Fatalf("bad header: %+v", m)
	}
	if m.Provider == nil || m.Provider.ID != "ble-battery" {
		t.Fatalf("bad provider: %+v", m.Provider)
	}
}

func TestDecodeDevicesAndState(t *testing.T) {
	dev := []byte(`{"type":"devices","devices":[{"id":"mx","name":"MX","entities":[{"key":"battery","kind":"sensor","unit":"%"}]}]}`)
	m, err := DecodeLine(dev)
	if err != nil {
		t.Fatal(err)
	}
	if len(m.Devices) != 1 || m.Devices[0].Entities[0].Key != "battery" {
		t.Fatalf("bad devices: %+v", m.Devices)
	}

	st := []byte(`{"type":"state","device":"mx","values":{"battery":55,"connected":true}}`)
	m2, err := DecodeLine(st)
	if err != nil {
		t.Fatal(err)
	}
	if m2.Device != "mx" {
		t.Fatalf("bad device: %q", m2.Device)
	}
	if v, ok := m2.Values["battery"].(float64); !ok || v != 55 {
		t.Fatalf("bad battery value: %v", m2.Values["battery"])
	}
}

func TestDecodeMalformedReturnsError(t *testing.T) {
	if _, err := DecodeLine([]byte(`not json`)); err == nil {
		t.Fatal("expected error for malformed line")
	}
}

func TestEncodeRoundTrip(t *testing.T) {
	m := Message{Type: "log", Level: "info", Message: "hi"}
	b, err := m.Encode()
	if err != nil {
		t.Fatal(err)
	}
	back, err := DecodeLine(b)
	if err != nil {
		t.Fatal(err)
	}
	if back.Level != "info" || back.Message != "hi" {
		t.Fatalf("round trip lost data: %+v", back)
	}
}

func TestCommandEncode(t *testing.T) {
	c := Command{Type: "refresh"}
	b, err := c.Encode()
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != `{"type":"refresh"}` {
		t.Fatalf("unexpected: %s", b)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `go test ./internal/protocol/`
Expected: FAIL — `undefined: DecodeLine`, `undefined: Message`, etc.

- [ ] **Step 3: Implement the protocol types and codec**

Create `internal/protocol/messages.go`:
```go
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/protocol/`
Expected: PASS (5 tests, `ok`).

- [ ] **Step 5: Commit**

```bash
git add internal/protocol
git commit -m "feat(protocol): ODB-PP/1 messages and JSONL codec"
```

---

## Task 2: HA discovery + state mapper (pure)

**Files:**
- Create: `internal/hapublish/mapper.go`
- Test: `internal/hapublish/mapper_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/hapublish/mapper_test.go`:
```go
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `go test ./internal/hapublish/`
Expected: FAIL — `undefined: Slug`, `undefined: DiscoveryMessages`, etc.

- [ ] **Step 3: Implement the mapper**

Create `internal/hapublish/mapper.go`:
```go
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
			"unique_id":              "odb_" + obj + "_" + e.Key,
			"object_id":              obj + "_" + e.Key,
			"name":                   titleize(e.Key),
			"state_topic":            state,
			"availability_topic":     BridgeAvailabilityTopic,
			"payload_available":      Available,
			"payload_not_available":  Unavailable,
			"device":                 device,
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/hapublish/`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add internal/hapublish/mapper.go internal/hapublish/mapper_test.go
git commit -m "feat(hapublish): generalized HA MQTT Discovery + state mapper"
```

---

## Task 3: MQTT client

**Files:**
- Create: `internal/hapublish/client.go`
- Test: `internal/hapublish/client_test.go`

- [ ] **Step 1: Add the paho dependency**

Run:
```bash
go get github.com/eclipse/paho.mqtt.golang@v1.5.0
```
Expected: updates `go.mod`/`go.sum`.

- [ ] **Step 2: Write the failing test (config construction is pure and testable)**

Create `internal/hapublish/client_test.go`:
```go
package hapublish

import "testing"

func TestBrokerURL(t *testing.T) {
	if got := brokerURL("192.168.31.150", 1883); got != "tcp://192.168.31.150:1883" {
		t.Fatalf("brokerURL=%q", got)
	}
}

func TestNewClientRequiresHost(t *testing.T) {
	if _, err := NewClient(Config{Host: "", Port: 1883}); err == nil {
		t.Fatal("expected error for empty host")
	}
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `go test ./internal/hapublish/ -run TestBroker`
Expected: FAIL — `undefined: brokerURL`, `undefined: NewClient`.

- [ ] **Step 4: Implement the MQTT client**

Create `internal/hapublish/client.go`:
```go
package hapublish

import (
	"errors"
	"fmt"
	"sync"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
)

// Config holds MQTT connection settings.
type Config struct {
	Host     string
	Port     int
	Username string
	Password string
	ClientID string
}

// Status is the connection state, surfaced to the UI.
type Status int

const (
	Disconnected Status = iota
	Connecting
	Connected
)

// Client wraps paho with HA-bridge semantics (LWT + availability).
type Client struct {
	cfg      Config
	client   mqtt.Client
	mu       sync.Mutex
	status   Status
	OnStatus func(Status)
}

func brokerURL(host string, port int) string {
	return fmt.Sprintf("tcp://%s:%d", host, port)
}

// NewClient validates config and constructs (but does not connect) a Client.
func NewClient(cfg Config) (*Client, error) {
	if cfg.Host == "" || cfg.Port <= 0 {
		return nil, errors.New("mqtt: host and port required")
	}
	if cfg.ClientID == "" {
		cfg.ClientID = "open-devices-bridge"
	}
	return &Client{cfg: cfg, status: Disconnected}, nil
}

func (c *Client) setStatus(s Status) {
	c.mu.Lock()
	changed := c.status != s
	c.status = s
	cb := c.OnStatus
	c.mu.Unlock()
	if changed && cb != nil {
		cb(s)
	}
}

// Connect establishes the MQTT connection with an offline LWT and, on connect,
// publishes the bridge availability as online.
func (c *Client) Connect() error {
	opts := mqtt.NewClientOptions().
		AddBroker(brokerURL(c.cfg.Host, c.cfg.Port)).
		SetClientID(c.cfg.ClientID).
		SetAutoReconnect(true).
		SetConnectRetry(true).
		SetConnectRetryInterval(5 * time.Second).
		SetKeepAlive(60 * time.Second).
		SetWill(BridgeAvailabilityTopic, Unavailable, 1, true)
	if c.cfg.Username != "" {
		opts.SetUsername(c.cfg.Username)
	}
	if c.cfg.Password != "" {
		opts.SetPassword(c.cfg.Password)
	}
	opts.OnConnect = func(cl mqtt.Client) {
		cl.Publish(BridgeAvailabilityTopic, 1, true, Available)
		c.setStatus(Connected)
	}
	opts.OnConnectionLost = func(cl mqtt.Client, err error) { c.setStatus(Connecting) }

	c.setStatus(Connecting)
	c.client = mqtt.NewClient(opts)
	tok := c.client.Connect()
	tok.Wait()
	return tok.Error()
}

// Publish sends one OutMessage.
func (c *Client) Publish(m OutMessage) {
	if c.client == nil {
		return
	}
	c.client.Publish(m.Topic, 1, m.Retained, m.Payload)
}

// Disconnect publishes offline and closes the connection.
func (c *Client) Disconnect() {
	if c.client != nil {
		c.client.Publish(BridgeAvailabilityTopic, 1, true, Unavailable).Wait()
		c.client.Disconnect(250)
	}
	c.setStatus(Disconnected)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `go test ./internal/hapublish/`
Expected: PASS (all hapublish tests).

- [ ] **Step 6: Commit**

```bash
git add internal/hapublish go.mod go.sum
git commit -m "feat(hapublish): MQTT client with HA bridge availability + LWT"
```

---

## Task 4: Provider process (launch, stream JSONL, restart)

**Files:**
- Create: `internal/provider/process.go`
- Test: `internal/provider/process_test.go`
- Test fixture: `internal/provider/testdata/echo_provider.sh`

- [ ] **Step 1: Create a fake provider script for tests**

Create `internal/provider/testdata/echo_provider.sh`:
```bash
#!/usr/bin/env bash
# Minimal fake provider: emits hello + devices + one state, then idles.
echo '{"type":"hello","protocol":1,"provider":{"id":"fake","name":"Fake","version":"0.0.1"}}'
echo '{"type":"devices","devices":[{"id":"d1","name":"D1","entities":[{"key":"battery","kind":"sensor","unit":"%"}]}]}'
echo '{"type":"state","device":"d1","values":{"battery":42}}'
# Stay alive so the host can observe a running process; exit on stdin close.
cat >/dev/null
```
Then: `chmod +x internal/provider/testdata/echo_provider.sh`

- [ ] **Step 2: Write the failing test**

Create `internal/provider/process_test.go`:
```go
package provider

import (
	"testing"
	"time"

	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
)

func TestProcessEmitsMessages(t *testing.T) {
	p := NewProcess("fake", "bash", []string{"testdata/echo_provider.sh"}, ".")
	msgs := make([]protocol.Message, 0, 3)
	done := make(chan struct{})
	p.OnMessage = func(m protocol.Message) {
		msgs = append(msgs, m)
		if len(msgs) == 3 {
			close(done)
		}
	}
	if err := p.Start(); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer p.Stop()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatalf("timeout; got %d messages", len(msgs))
	}
	if msgs[0].Type != "hello" || msgs[0].Protocol != 1 {
		t.Fatalf("first msg not hello: %+v", msgs[0])
	}
	if msgs[2].Type != "state" || msgs[2].Values["battery"].(float64) != 42 {
		t.Fatalf("third msg not state: %+v", msgs[2])
	}
}

func TestProcessSendCommand(t *testing.T) {
	p := NewProcess("fake", "bash", []string{"testdata/echo_provider.sh"}, ".")
	if err := p.Start(); err != nil {
		t.Fatal(err)
	}
	defer p.Stop()
	// Should not error writing a command to stdin.
	if err := p.Send(protocol.Command{Type: "refresh"}); err != nil {
		t.Fatalf("send: %v", err)
	}
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `go test ./internal/provider/ -run TestProcess`
Expected: FAIL — `undefined: NewProcess`.

- [ ] **Step 4: Implement the process wrapper**

Create `internal/provider/process.go`:
```go
// Package provider launches and manages out-of-process device providers.
package provider

import (
	"bufio"
	"io"
	"os/exec"
	"sync"

	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
)

// Process runs one provider executable and streams its JSONL messages.
type Process struct {
	id      string
	command string
	args    []string
	dir     string

	OnMessage func(protocol.Message)
	OnExit    func(error)
	OnLogLine func(string) // raw lines that fail to parse, for diagnostics

	mu    sync.Mutex
	cmd   *exec.Cmd
	stdin io.WriteCloser
}

// NewProcess creates (but does not start) a provider process.
func NewProcess(id, command string, args []string, dir string) *Process {
	return &Process{id: id, command: command, args: args, dir: dir}
}

// Start launches the process and begins reading stdout.
func (p *Process) Start() error {
	cmd := exec.Command(p.command, p.args...)
	cmd.Dir = p.dir

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}

	p.mu.Lock()
	p.cmd = cmd
	p.stdin = stdin
	p.mu.Unlock()

	go p.readLoop(stdout)
	go func() {
		err := cmd.Wait()
		if p.OnExit != nil {
			p.OnExit(err)
		}
	}()
	return nil
}

func (p *Process) readLoop(stdout io.Reader) {
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := sc.Bytes()
		if len(line) == 0 {
			continue
		}
		m, err := protocol.DecodeLine(line)
		if err != nil {
			if p.OnLogLine != nil {
				p.OnLogLine(string(line))
			}
			continue
		}
		if p.OnMessage != nil {
			p.OnMessage(m)
		}
	}
}

// Send writes a host→provider command to the process stdin.
func (p *Process) Send(c protocol.Command) error {
	b, err := c.Encode()
	if err != nil {
		return err
	}
	p.mu.Lock()
	w := p.stdin
	p.mu.Unlock()
	if w == nil {
		return io.ErrClosedPipe
	}
	_, err = w.Write(append(b, '\n'))
	return err
}

// Stop closes stdin (signalling shutdown) and kills the process.
func (p *Process) Stop() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.stdin != nil {
		_ = p.stdin.Close()
	}
	if p.cmd != nil && p.cmd.Process != nil {
		_ = p.cmd.Process.Kill()
	}
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `go test ./internal/provider/ -run TestProcess`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add internal/provider
git commit -m "feat(provider): subprocess wrapper streaming JSONL messages"
```

---

## Task 5: Provider registry + supervisor (discovery + restart)

**Files:**
- Create: `internal/provider/registry.go`
- Create: `internal/provider/supervisor.go`
- Test: `internal/provider/registry_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/provider/registry_test.go`:
```go
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `go test ./internal/provider/ -run TestDiscover`
Expected: FAIL — `undefined: Discover`.

- [ ] **Step 3: Implement the registry**

Create `internal/provider/registry.go`:
```go
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/provider/ -run TestDiscover -run TestManifest`
Expected: PASS.

- [ ] **Step 5: Add the supervisor (restart with backoff)**

Create `internal/provider/supervisor.go`:
```go
package provider

import (
	"sync"
	"time"

	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
)

// Supervisor keeps a provider process running, restarting it with exponential
// backoff (1s→60s) when it exits.
type Supervisor struct {
	manifest Manifest
	onMsg    func(providerID string, m protocol.Message)
	onDown   func(providerID string)

	mu      sync.Mutex
	proc    *Process
	stopped bool
	backoff time.Duration
}

// NewSupervisor wires a manifest to message and down callbacks.
func NewSupervisor(m Manifest,
	onMsg func(providerID string, msg protocol.Message),
	onDown func(providerID string)) *Supervisor {
	return &Supervisor{manifest: m, onMsg: onMsg, onDown: onDown, backoff: time.Second}
}

// Start launches and supervises the provider.
func (s *Supervisor) Start() {
	s.launch()
}

func (s *Supervisor) launch() {
	s.mu.Lock()
	if s.stopped {
		s.mu.Unlock()
		return
	}
	cmd, args := s.manifest.Command()
	p := NewProcess(s.manifest.ID, cmd, args, s.manifest.Dir)
	id := s.manifest.ID
	p.OnMessage = func(m protocol.Message) {
		s.mu.Lock()
		s.backoff = time.Second // healthy traffic resets backoff
		s.mu.Unlock()
		s.onMsg(id, m)
	}
	p.OnExit = func(error) {
		if s.onDown != nil {
			s.onDown(id)
		}
		s.scheduleRestart()
	}
	s.proc = p
	s.mu.Unlock()

	if err := p.Start(); err != nil {
		if s.onDown != nil {
			s.onDown(id)
		}
		s.scheduleRestart()
	}
}

func (s *Supervisor) scheduleRestart() {
	s.mu.Lock()
	if s.stopped {
		s.mu.Unlock()
		return
	}
	d := s.backoff
	if s.backoff < 60*time.Second {
		s.backoff *= 2
	}
	s.mu.Unlock()
	time.AfterFunc(d, s.launch)
}

// Send forwards a command to the running provider.
func (s *Supervisor) Send(c protocol.Command) {
	s.mu.Lock()
	p := s.proc
	s.mu.Unlock()
	if p != nil {
		_ = p.Send(c)
	}
}

// Stop permanently stops the provider.
func (s *Supervisor) Stop() {
	s.mu.Lock()
	s.stopped = true
	p := s.proc
	s.mu.Unlock()
	if p != nil {
		p.Stop()
	}
}
```

- [ ] **Step 6: Run all provider tests**

Run: `go test ./internal/provider/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add internal/provider
git commit -m "feat(provider): registry discovery + supervisor with restart backoff"
```

---

## Task 6: Config (settings file + keyring password)

**Files:**
- Create: `internal/config/config.go`
- Test: `internal/config/config_test.go`

- [ ] **Step 1: Add the keyring dependency**

Run:
```bash
go get github.com/zalando/go-keyring@v0.2.5
```

- [ ] **Step 2: Write the failing test**

Create `internal/config/config_test.go`:
```go
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
```

- [ ] **Step 3: Run it to verify it fails**

Run: `go test ./internal/config/`
Expected: FAIL — `undefined: Settings`, `undefined: saveTo`.

- [ ] **Step 4: Implement config**

Create `internal/config/config.go`:
```go
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `go test ./internal/config/`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add internal/config go.mod go.sum
git commit -m "feat(config): settings file + keyring-backed MQTT password"
```

---

## Task 7: host-info Python provider

**Files:**
- Create: `providers/host-info/host_info.py`
- Create: `providers/host-info/provider.json`
- Test: `internal/provider/selftest_test.go`

- [ ] **Step 1: Write the provider**

Create `providers/host-info/host_info.py`:
```python
#!/usr/bin/env python3
"""host-info provider: publishes the host machine's battery + online state.

Speaks ODB Provider Protocol v1 (JSONL on stdout). Stdlib only.
"""
import json
import subprocess
import sys
import time

PROVIDER = {"id": "host-info", "name": "Host Info", "version": "1.0.0"}
DEVICE_ID = "this-host"


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def host_battery():
    """Return host battery percent (int) or None, via `pmset -g batt` on macOS."""
    try:
        out = subprocess.run(["pmset", "-g", "batt"], capture_output=True,
                             text=True, timeout=5).stdout
    except Exception:
        return None
    for token in out.replace(";", " ").split():
        if token.endswith("%"):
            try:
                return int(token[:-1])
            except ValueError:
                return None
    return None


def devices_message():
    return {
        "type": "devices",
        "devices": [{
            "id": DEVICE_ID,
            "name": "This Host",
            "manufacturer": "Open Devices Bridge",
            "model": "host-info",
            "entities": [
                {"key": "battery", "kind": "sensor", "device_class": "battery", "unit": "%"},
                {"key": "online", "kind": "binary_sensor", "device_class": "connectivity"},
            ],
        }],
    }


def state_message():
    return {"type": "state", "device": DEVICE_ID,
            "values": {"battery": host_battery(), "online": True}}


def selftest():
    emit({"type": "hello", "protocol": 1, "provider": PROVIDER})
    emit(devices_message())
    emit(state_message())


def run():
    emit({"type": "hello", "protocol": 1, "provider": PROVIDER})
    emit(devices_message())
    while True:
        emit(state_message())
        time.sleep(60)


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        run()
```
Then: `chmod +x providers/host-info/host_info.py`

- [ ] **Step 2: Write the manifest**

Create `providers/host-info/provider.json`:
```json
{
  "id": "host-info",
  "name": "Host Info",
  "exec": "host_info.py",
  "args": [],
  "platforms": ["darwin", "linux", "windows"],
  "enabled": true
}
```

- [ ] **Step 3: Write the failing integration test**

Create `internal/provider/selftest_test.go`:
```go
package provider

import (
	"os/exec"
	"strings"
	"testing"

	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
)

// The real Python provider must emit a valid hello+devices+state.
func TestHostInfoSelftest(t *testing.T) {
	out, err := exec.Command("python3", "../../providers/host-info/host_info.py", "--selftest").Output()
	if err != nil {
		t.Fatalf("selftest run: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) != 3 {
		t.Fatalf("want 3 lines, got %d: %q", len(lines), out)
	}
	hello, err := protocol.DecodeLine([]byte(lines[0]))
	if err != nil || hello.Type != "hello" || hello.Protocol != 1 {
		t.Fatalf("bad hello: %v / %+v", err, hello)
	}
	devs, _ := protocol.DecodeLine([]byte(lines[1]))
	if devs.Type != "devices" || len(devs.Devices) != 1 {
		t.Fatalf("bad devices: %+v", devs)
	}
	st, _ := protocol.DecodeLine([]byte(lines[2]))
	if st.Type != "state" || st.Device != "this-host" {
		t.Fatalf("bad state: %+v", st)
	}
	if _, ok := st.Values["online"]; !ok {
		t.Fatalf("state missing online: %+v", st.Values)
	}
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `go test ./internal/provider/ -run TestHostInfoSelftest`
Expected: PASS (the script exists and emits valid protocol).

- [ ] **Step 5: Commit**

```bash
git add providers/host-info internal/provider/selftest_test.go
git commit -m "feat(providers): host-info Python provider + selftest integration test"
```

---

## Task 8: ble-battery Swift provider

**Files:**
- Create: `providers/ble-battery/Package.swift`
- Create: `providers/ble-battery/Sources/ble-battery/main.swift`
- Create: `providers/ble-battery/provider.json`
- Modify: `providers/ble-battery/Sources/ble-battery/BatteryReader.swift` (already moved in Task 0; make `Self`-namespaced symbols `public`-free since single target)

- [ ] **Step 1: Write the SwiftPM manifest**

Create `providers/ble-battery/Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ble-battery",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ble-battery",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Strip `public` access modifiers from the moved reader**

The reader was a library type; in a single executable target it needs no
`public`. In `providers/ble-battery/Sources/ble-battery/BatteryReader.swift` and
`DeviceReading.swift`, remove every `public ` prefix (the types stay internal to
the executable). Run a check:
```bash
grep -rn "public " providers/ble-battery/Sources || echo "no public modifiers left"
```
Expected: `no public modifiers left`.

- [ ] **Step 3: Write the provider entrypoint that speaks JSONL**

Create `providers/ble-battery/Sources/ble-battery/main.swift`:
```swift
import Foundation

// ODB-PP/1 provider wrapping BatteryReader. Emits hello + devices + state JSONL
// on stdout; honors {"type":"refresh"} / {"type":"shutdown"} on stdin.

let stdoutQueue = DispatchQueue(label: "stdout")

func emit(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          var s = String(data: data, encoding: .utf8) else { return }
    s += "\n"
    stdoutQueue.sync { FileHandle.standardOutput.write(Data(s.utf8)) }
}

let provider = BatteryReader()
var announcedDevices = Set<String>()

func slug(_ s: String) -> String {
    var out = "", lastUnderscore = false
    for ch in s.lowercased() {
        if ch.isLetter || ch.isNumber { out.append(ch); lastUnderscore = false }
        else if !lastUnderscore { out.append("_"); lastUnderscore = true }
    }
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "device" : trimmed
}

func publish(_ readings: [DeviceReading]) {
    // Announce devices once (or when a new one appears).
    let newOnes = readings.filter { !announcedDevices.contains($0.id) }
    if !newOnes.isEmpty {
        let devices: [[String: Any]] = readings.map { r in
            [
                "id": slug(r.name),
                "name": r.name,
                "manufacturer": "Logitech",
                "model": r.name,
                "entities": [
                    ["key": "battery", "kind": "sensor", "device_class": "battery", "unit": "%"],
                    ["key": "connected", "kind": "binary_sensor", "device_class": "connectivity"],
                    ["key": "firmware", "kind": "sensor", "entity_category": "diagnostic"],
                ],
            ]
        }
        emit(["type": "devices", "devices": devices])
        readings.forEach { announcedDevices.insert($0.id) }
    }
    for r in readings {
        emit([
            "type": "state",
            "device": slug(r.name),
            "values": [
                "battery": r.battery as Any? ?? NSNull(),
                "connected": r.online,
                "firmware": r.firmware as Any? ?? NSNull(),
            ],
        ])
    }
}

func poll() { provider.refresh { readings in publish(readings) } }

// Hello first.
emit(["type": "hello", "protocol": 1,
      "provider": ["id": "ble-battery", "name": "BLE Battery", "version": "1.0.0"]])

// Poll on a timer; also poll once Bluetooth is powered on.
provider.onStateChange = { state in if state == .poweredOn { poll() } }
let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in poll() }
RunLoop.main.add(timer, forMode: .common)

// Read stdin commands on a background thread.
DispatchQueue.global().async {
    while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { continue }
        switch type {
        case "refresh": poll()
        case "shutdown": exit(0)
        default: break
        }
    }
}

poll()
RunLoop.main.run()
```

- [ ] **Step 4: Write the manifest**

Create `providers/ble-battery/provider.json`:
```json
{
  "id": "ble-battery",
  "name": "BLE Battery",
  "exec": "ble-battery",
  "args": [],
  "platforms": ["darwin"],
  "enabled": true
}
```

- [ ] **Step 5: Build the provider and smoke-test it speaks the protocol**

Run:
```bash
cd providers/ble-battery && swift build -c release
.build/release/ble-battery & PID=$!
sleep 6
kill $PID
cd ../..
```
Expected: stdout shows a `hello` line, a `devices` line, and `state` lines with
`"battery"` values (the connected MX devices). Confirms the provider works.

- [ ] **Step 6: Commit**

```bash
git add providers/ble-battery
git commit -m "feat(providers): ble-battery Swift provider speaking ODB-PP/1"
```

---

## Task 9: Orchestrator (wire registry → providers → mapper → MQTT)

**Files:**
- Create: `internal/app/orchestrator.go`
- Test: `internal/app/orchestrator_test.go`

- [ ] **Step 1: Write the failing test (state aggregation is pure-ish)**

Create `internal/app/orchestrator_test.go`:
```go
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `go test ./internal/app/`
Expected: FAIL — `undefined: newStore`.

- [ ] **Step 3: Implement the store + orchestrator**

Create `internal/app/orchestrator.go`:
```go
// Package app wires providers, the HA mapper, and the MQTT client together.
package app

import (
	"sync"

	"github.com/hudsonbrendon/open-devices-bridge/internal/hapublish"
	"github.com/hudsonbrendon/open-devices-bridge/internal/protocol"
	"github.com/hudsonbrendon/open-devices-bridge/internal/provider"
)

// store holds the latest devices + values per provider for the UI.
type store struct {
	mu      sync.Mutex
	devices map[string][]protocol.Device          // providerID -> devices
	values  map[string]map[string]map[string]any  // providerID -> deviceID -> values
}

func newStore() *store {
	return &store{
		devices: map[string][]protocol.Device{},
		values:  map[string]map[string]map[string]any{},
	}
}

func (s *store) setDevices(providerID string, d []protocol.Device) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.devices[providerID] = d
}

func (s *store) setValues(providerID, deviceID string, v map[string]any) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.values[providerID] == nil {
		s.values[providerID] = map[string]map[string]any{}
	}
	s.values[providerID][deviceID] = v
}

func (s *store) deviceValues(providerID, deviceID string) map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.values[providerID][deviceID]
}

func (s *store) snapshot() map[string][]protocol.Device {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string][]protocol.Device{}
	for k, v := range s.devices {
		out[k] = v
	}
	return out
}

// Orchestrator owns the running providers and the MQTT client.
type Orchestrator struct {
	client      *hapublish.Client
	store       *store
	supervisors []*provider.Supervisor
	infos       map[string]protocol.ProviderInfo
	mu          sync.Mutex

	OnUpdate func() // notify UI of new data
}

// NewOrchestrator constructs an orchestrator with an MQTT client.
func NewOrchestrator(client *hapublish.Client) *Orchestrator {
	return &Orchestrator{client: client, store: newStore(), infos: map[string]protocol.ProviderInfo{}}
}

// Start discovers providers in roots and launches each under a supervisor.
func (o *Orchestrator) Start(roots []string) {
	for _, m := range provider.Discover(roots) {
		sup := provider.NewSupervisor(m, o.handleMessage, o.handleDown)
		o.supervisors = append(o.supervisors, sup)
		sup.Start()
	}
}

func (o *Orchestrator) handleMessage(providerID string, m protocol.Message) {
	switch m.Type {
	case "hello":
		if m.Provider != nil {
			o.mu.Lock()
			o.infos[providerID] = *m.Provider
			o.mu.Unlock()
		}
	case "devices":
		o.store.setDevices(providerID, m.Devices)
		o.mu.Lock()
		info := o.infos[providerID]
		o.mu.Unlock()
		for _, d := range m.Devices {
			for _, msg := range hapublish.DiscoveryMessages(info, d) {
				o.client.Publish(msg)
			}
		}
	case "state":
		o.store.setValues(providerID, m.Device, m.Values)
		o.mu.Lock()
		devices := o.store.devices[providerID]
		o.mu.Unlock()
		for _, d := range devices {
			if d.ID == m.Device {
				o.client.Publish(hapublish.StateMessage(providerID, d, m.Values))
			}
		}
	}
	if o.OnUpdate != nil {
		o.OnUpdate()
	}
}

func (o *Orchestrator) handleDown(providerID string) {
	if o.OnUpdate != nil {
		o.OnUpdate()
	}
}

// Snapshot exposes current devices for the UI.
func (o *Orchestrator) Snapshot() map[string][]protocol.Device { return o.store.snapshot() }

// Values exposes current values for a device.
func (o *Orchestrator) Values(providerID, deviceID string) map[string]any {
	return o.store.deviceValues(providerID, deviceID)
}

// Stop stops all providers.
func (o *Orchestrator) Stop() {
	for _, s := range o.supervisors {
		s.Stop()
	}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/app/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/app
git commit -m "feat(app): orchestrator wiring providers to HA discovery + state"
```

---

## Task 10: Fyne tray + settings UI and main entrypoint

**Files:**
- Create: `internal/ui/tray.go`
- Create: `internal/ui/settings.go`
- Create: `cmd/odb/main.go`

- [ ] **Step 1: Add the Fyne dependency**

Run:
```bash
go get fyne.io/fyne/v2@v2.5.3
```

- [ ] **Step 2: Implement the settings window**

Create `internal/ui/settings.go`:
```go
package ui

import (
	"strconv"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"

	"github.com/hudsonbrendon/open-devices-bridge/internal/config"
)

// ShowSettings opens a settings window; onSave is called with new settings.
func ShowSettings(app fyne.App, current config.Settings, onSave func(config.Settings, string)) {
	w := app.NewWindow("Open Devices Bridge — Configurações")

	host := widget.NewEntry()
	host.SetText(current.Host)
	port := widget.NewEntry()
	port.SetText(strconv.Itoa(current.Port))
	user := widget.NewEntry()
	user.SetText(current.Username)
	pass := widget.NewPasswordEntry()
	pass.SetText(config.Password())
	interval := widget.NewEntry()
	interval.SetText(strconv.Itoa(current.IntervalMinutes))

	form := widget.NewForm(
		widget.NewFormItem("Broker (host)", host),
		widget.NewFormItem("Porta", port),
		widget.NewFormItem("Usuário", user),
		widget.NewFormItem("Senha", pass),
		widget.NewFormItem("Intervalo (min)", interval),
	)
	form.OnSubmit = func() {
		p, _ := strconv.Atoi(port.Text)
		iv, _ := strconv.Atoi(interval.Text)
		if iv < 1 {
			iv = 5
		}
		s := config.Settings{Host: host.Text, Port: p, Username: user.Text, IntervalMinutes: iv}
		onSave(s, pass.Text)
		w.Close()
	}
	form.SubmitText = "Salvar"

	w.SetContent(container.NewVBox(form))
	w.Resize(fyne.NewSize(420, 320))
	w.Show()
}
```

- [ ] **Step 3: Implement the tray**

Create `internal/ui/tray.go`:
```go
package ui

import (
	"fmt"
	"sort"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/driver/desktop"

	"github.com/hudsonbrendon/open-devices-bridge/internal/app"
	"github.com/hudsonbrendon/open-devices-bridge/internal/hapublish"
)

// BuildTray installs the system-tray menu reflecting current devices + status.
func BuildTray(fa fyne.App, orch *app.Orchestrator, status hapublish.Status,
	onSettings, onRefresh, onQuit func()) {
	desk, ok := fa.(desktop.App)
	if !ok {
		return
	}
	items := []*fyne.MenuItem{}

	snap := orch.Snapshot()
	providers := make([]string, 0, len(snap))
	for p := range snap {
		providers = append(providers, p)
	}
	sort.Strings(providers)
	for _, p := range providers {
		for _, d := range snap[p] {
			vals := orch.Values(p, d.ID)
			label := d.Name
			if b, ok := vals["battery"]; ok && b != nil {
				label = fmt.Sprintf("%s: %v%%", d.Name, b)
			}
			mi := fyne.NewMenuItem(label, nil)
			mi.Disabled = true
			items = append(items, mi)
		}
	}
	if len(items) == 0 {
		mi := fyne.NewMenuItem("Nenhum dispositivo", nil)
		mi.Disabled = true
		items = append(items, mi)
	}
	statusItem := fyne.NewMenuItem("MQTT: "+statusLabel(status), nil)
	statusItem.Disabled = true
	items = append(items,
		fyne.NewMenuItemSeparator(),
		statusItem,
		fyne.NewMenuItemSeparator(),
		fyne.NewMenuItem("Atualizar agora", onRefresh),
		fyne.NewMenuItem("Configurações…", onSettings),
		fyne.NewMenuItem("Sair", onQuit),
	)
	desk.SetSystemTrayMenu(fyne.NewMenu("Open Devices Bridge", items...))
}

func statusLabel(s hapublish.Status) string {
	switch s {
	case hapublish.Connected:
		return "conectado"
	case hapublish.Connecting:
		return "conectando…"
	default:
		return "desconectado"
	}
}
```

- [ ] **Step 4: Implement main**

Create `cmd/odb/main.go`:
```go
package main

import (
	"os"
	"path/filepath"
	"time"

	fyneapp "fyne.io/fyne/v2/app"

	appcore "github.com/hudsonbrendon/open-devices-bridge/internal/app"
	"github.com/hudsonbrendon/open-devices-bridge/internal/config"
	"github.com/hudsonbrendon/open-devices-bridge/internal/hapublish"
	"github.com/hudsonbrendon/open-devices-bridge/internal/ui"
)

func providerRoots() []string {
	roots := []string{}
	// Bundled providers next to the executable: <app>/Contents/Resources/providers
	if exe, err := os.Executable(); err == nil {
		roots = append(roots, filepath.Join(filepath.Dir(exe), "..", "Resources", "providers"))
		roots = append(roots, filepath.Join(filepath.Dir(exe), "providers")) // dev layout
	}
	// User-installed providers
	if dir, err := os.UserConfigDir(); err == nil {
		roots = append(roots, filepath.Join(dir, "OpenDevicesBridge", "providers"))
	}
	return roots
}

func main() {
	fa := fyneapp.NewWithID("online.99lab.opendevicesbridge")

	settings, _ := config.Load()
	client, err := hapublish.NewClient(hapublish.Config{
		Host: settings.Host, Port: settings.Port,
		Username: settings.Username, Password: config.Password(),
		ClientID: "open-devices-bridge",
	})

	orch := appcore.NewOrchestrator(client)

	rebuild := func() {
		ui.BuildTray(fa, orch, currentStatus(client),
			func() { ui.ShowSettings(fa, settings, func(s config.Settings, pw string) {
				config.Save(s)
				config.SetPassword(pw)
				settings = s
			}) },
			func() { /* refresh handled by providers' own timers in SP1 */ },
			func() { orch.Stop(); client.Disconnect(); fa.Quit() },
		)
	}

	if client != nil && err == nil {
		client.OnStatus = func(hapublish.Status) { rebuild() }
		go client.Connect()
	}

	orch.OnUpdate = rebuild
	orch.Start(providerRoots())
	rebuild()

	// Periodic UI refresh as a safety net.
	go func() {
		for range time.Tick(30 * time.Second) {
			rebuild()
		}
	}()

	fa.Run()
}

func currentStatus(c *hapublish.Client) hapublish.Status {
	if c == nil {
		return hapublish.Disconnected
	}
	return hapublish.Connected // refined via OnStatus callbacks
}
```

> **Note on import aliasing:** `cmd/odb/main.go` imports both Fyne's `app` and our
> `internal/app`. The imports above alias them `fyneapp` and `appcore` respectively
> so they don't collide. Keep both aliases consistent throughout the file.

- [ ] **Step 5: Build and smoke-test**

Run:
```bash
go build ./...
go run ./cmd/odb & PID=$!
sleep 8
kill $PID
```
Expected: builds clean; a tray icon appears (manually confirm the menu lists
`This Host` from host-info and, if a broker is configured, connects). No crash.

- [ ] **Step 6: Commit**

```bash
git add internal/ui cmd go.mod go.sum
git commit -m "feat(ui): Fyne tray + settings window and odb entrypoint"
```

---

## Task 11: macOS packaging (.app + .dmg) with bundled providers

**Files:**
- Create: `packaging/Info.plist`
- Create: `scripts/build-app.sh`
- Create: `scripts/build-dmg.sh`
- Delete: old `Package.swift`-based scripts if any remain

- [ ] **Step 1: Write the rebranded Info.plist**

Create `packaging/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Open Devices Bridge</string>
    <key>CFBundleDisplayName</key><string>Open Devices Bridge</string>
    <key>CFBundleIdentifier</key><string>online.99lab.opendevicesbridge</string>
    <key>CFBundleExecutable</key><string>odb</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>O Open Devices Bridge lê o nível de bateria dos seus dispositivos Bluetooth pareados para publicar no Home Assistant.</string>
</dict>
</plist>
```

- [ ] **Step 2: Write build-app.sh (Go host + Swift provider + bundled providers)**

Create `scripts/build-app.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Open Devices Bridge.app"
RES="$APP/Contents/Resources"

echo "==> build Go host"
go build -o build/odb ./cmd/odb

echo "==> build Swift ble-battery provider"
( cd providers/ble-battery && swift build -c release )

echo "==> assemble bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES/providers/ble-battery" "$RES/providers/host-info"
cp build/odb "$APP/Contents/MacOS/odb"
cp packaging/Info.plist "$APP/Contents/Info.plist"

# ble-battery: the built binary + its manifest
cp providers/ble-battery/.build/release/ble-battery "$RES/providers/ble-battery/ble-battery"
cp providers/ble-battery/provider.json "$RES/providers/ble-battery/provider.json"

# host-info: the script + manifest
cp providers/host-info/host_info.py "$RES/providers/host-info/host_info.py"
cp providers/host-info/provider.json "$RES/providers/host-info/provider.json"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - --options runtime \
  --identifier online.99lab.opendevicesbridge "$APP"
echo "==> done: $APP"
```
Then: `chmod +x scripts/build-app.sh`

- [ ] **Step 3: Write build-dmg.sh**

Create `scripts/build-dmg.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh

APP="build/Open Devices Bridge.app"
DMG="build/Open-Devices-Bridge.dmg"
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Open Devices Bridge" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "==> done: $DMG (unsigned; first run: right-click > Open, or xattr -dr com.apple.quarantine)"
```
Then: `chmod +x scripts/build-dmg.sh`

- [ ] **Step 4: Build the DMG and verify providers are bundled**

Run:
```bash
bash scripts/build-dmg.sh
ls "build/Open Devices Bridge.app/Contents/Resources/providers"
```
Expected: lists `ble-battery` and `host-info`; `build/Open-Devices-Bridge.dmg` exists.

- [ ] **Step 5: Commit**

```bash
git add packaging scripts
git commit -m "build: macOS .app/.dmg packaging with bundled providers"
```

---

## Task 12: CI — build the DMG (Go + Swift)

**Files:**
- Modify: `.github/workflows/build.yml`

- [ ] **Step 1: Replace the workflow**

Overwrite `.github/workflows/build.yml`:
```yaml
name: Build DMG

on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: "1.23"

      - name: Select latest stable Xcode (Swift 6)
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Go tests
        run: go test ./...

      - name: Build .dmg
        run: bash scripts/build-dmg.sh

      - name: Upload .dmg artifact
        uses: actions/upload-artifact@v4
        with:
          name: Open-Devices-Bridge-dmg
          path: build/Open-Devices-Bridge.dmg
          if-no-files-found: error

      - name: Attach .dmg to release (on tag)
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: build/Open-Devices-Bridge.dmg
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: build Go host + Swift provider into the DMG"
```

---

## Task 13: README rewrite + GitHub repo rename

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite the README**

Overwrite `README.md`:
```markdown
# Open Devices Bridge

A cross-platform, community-extensible bridge that discovers devices on your
machine and publishes them to **Home Assistant** over **MQTT Discovery** —
in the spirit of OpenRGB, but for telemetry (battery, presence, firmware) with
control planned.

Support is added through **providers**: small executables the host launches that
speak a simple line-delimited JSON protocol (ODB-PP/1). Providers can be written
in any language; the host is written in Go and runs on macOS today
(Windows/Linux planned).

## Bundled providers

- **ble-battery** (macOS, Swift) — battery, connection and firmware of paired BLE
  devices (e.g. Logitech MX Keys Mini, MX Master 3) via CoreBluetooth.
- **host-info** (any OS, Python) — the host machine's own battery + online state.

## Build & run (macOS)

Requires Go 1.23+, Swift (Command Line Tools), Python 3.

```bash
go test ./...                 # core tests
bash scripts/build-dmg.sh     # => build/Open-Devices-Bridge.dmg
```

Install: copy **Open Devices Bridge.app** to `/Applications`. First launch asks
for **Bluetooth** permission (needed by the ble-battery provider). The app is
unsigned; on first open right-click → **Open**, or:
```bash
xattr -dr com.apple.quarantine "/Applications/Open Devices Bridge.app"
```

Configure the broker in the tray → **Configurações…** (requires the Mosquitto
add-on + MQTT integration in Home Assistant).

## Writing a provider

A provider is a directory under `providers/` (bundled) or
`~/Library/Application Support/OpenDevicesBridge/providers/` (user) containing a
`provider.json` and an executable. On launch it prints `hello`, then `devices`,
then `state` lines on stdout. See `docs/superpowers/specs/` for the protocol.

## Roadmap

- SP2 — real device providers (Stream Deck, Logitech webcam, Keychron K3) + control.
- SP3 — Windows/Linux host packaging + per-OS providers.
- SP4 — community provider registry.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for Open Devices Bridge"
```

- [ ] **Step 3: Rename the GitHub repository**

Run:
```bash
gh repo rename open-devices-bridge --repo hudsonbrendon/ha-battery-bridge --yes
git remote set-url origin git@github.com:hudsonbrendon/open-devices-bridge.git
git push origin main
```
Expected: repo renamed (GitHub redirects the old name); `main` pushed.

- [ ] **Step 4: Tag a release to produce the new DMG**

```bash
git tag v2.0.0
git push origin v2.0.0
```
Expected: CI builds and attaches `Open-Devices-Bridge.dmg` to release `v2.0.0`.

---

## Self-Review notes (addressed)

- **Spec coverage:** protocol (T1), HA mapping (T2), MQTT (T3), provider process
  (T4), registry+supervisor (T5), config (T6), host-info (T7), ble-battery (T8),
  orchestrator (T9), tray+settings+main (T10), packaging (T11), CI (T12), README +
  rename (T13). All spec sections map to a task.
- **Type consistency:** `protocol.Message`/`Command`, `hapublish.OutMessage`/
  `Config`/`Status`/`Client`, `provider.Manifest`/`Process`/`Supervisor`/`Discover`,
  `config.Settings`, `app.Orchestrator` are used with identical signatures across
  tasks. The `internal/app` package is imported as `appcore` in `main.go` to avoid
  colliding with `fyne.io/fyne/v2/app`.
- **Deferred-by-design:** control kinds, Windows/Linux packaging, provider
  marketplace — all out of SP1 scope per the spec.
```
