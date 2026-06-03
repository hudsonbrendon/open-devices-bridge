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
