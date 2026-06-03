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
