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
