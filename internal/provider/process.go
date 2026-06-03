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
