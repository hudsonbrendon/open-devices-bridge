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
