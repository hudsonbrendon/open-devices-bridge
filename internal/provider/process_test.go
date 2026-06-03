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
