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
	if exe, err := os.Executable(); err == nil {
		roots = append(roots, filepath.Join(filepath.Dir(exe), "..", "Resources", "providers"))
		roots = append(roots, filepath.Join(filepath.Dir(exe), "providers")) // dev layout
	}
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
			func() {
				ui.ShowSettings(fa, settings, func(s config.Settings, pw string) {
					config.Save(s)
					config.SetPassword(pw)
					settings = s
				})
			},
			func() {},
			func() {
				orch.Stop()
				if client != nil {
					client.Disconnect()
				}
				fa.Quit()
			},
		)
	}

	if client != nil && err == nil {
		client.OnStatus = func(hapublish.Status) { rebuild() }
		go client.Connect()
	}

	orch.OnUpdate = rebuild
	orch.Start(providerRoots())
	rebuild()

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
	return hapublish.Connected
}
