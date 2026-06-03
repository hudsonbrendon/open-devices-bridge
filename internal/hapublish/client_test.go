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
