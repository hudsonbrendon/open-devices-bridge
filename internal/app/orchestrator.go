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
	devices map[string][]protocol.Device         // providerID -> devices
	values  map[string]map[string]map[string]any // providerID -> deviceID -> values
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

// devicesFor returns a copy of the device slice for a provider (store mutex only).
func (s *store) devicesFor(providerID string) []protocol.Device {
	s.mu.Lock()
	defer s.mu.Unlock()
	devs := s.devices[providerID]
	out := make([]protocol.Device, len(devs))
	copy(out, devs)
	return out
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
		if o.client != nil {
			o.mu.Lock()
			info := o.infos[providerID]
			o.mu.Unlock()
			for _, d := range m.Devices {
				for _, msg := range hapublish.DiscoveryMessages(info, d) {
					o.client.Publish(msg)
				}
			}
		}
	case "state":
		o.store.setValues(providerID, m.Device, m.Values)
		// Use devicesFor to read under the store's own mutex (avoids mixing o.mu and store.mu).
		devices := o.store.devicesFor(providerID)
		if o.client != nil {
			for _, d := range devices {
				if d.ID == m.Device {
					o.client.Publish(hapublish.StateMessage(providerID, d, m.Values))
				}
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
