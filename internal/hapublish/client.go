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
		SetConnectRetryInterval(5*time.Second).
		SetKeepAlive(60*time.Second).
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
	if c == nil || c.client == nil {
		return
	}
	c.client.Publish(m.Topic, 1, m.Retained, m.Payload)
}

// Disconnect publishes offline and closes the connection.
func (c *Client) Disconnect() {
	if c == nil {
		return
	}
	if c.client != nil {
		c.client.Publish(BridgeAvailabilityTopic, 1, true, Unavailable).Wait()
		c.client.Disconnect(250)
	}
	c.setStatus(Disconnected)
}
