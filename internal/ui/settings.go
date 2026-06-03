package ui

import (
	"strconv"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"

	"github.com/hudsonbrendon/open-devices-bridge/internal/config"
)

// ShowSettings opens a settings window; onSave is called with new settings.
func ShowSettings(app fyne.App, current config.Settings, onSave func(config.Settings, string)) {
	w := app.NewWindow("Open Devices Bridge — Configurações")

	host := widget.NewEntry()
	host.SetText(current.Host)
	port := widget.NewEntry()
	port.SetText(strconv.Itoa(current.Port))
	user := widget.NewEntry()
	user.SetText(current.Username)
	pass := widget.NewPasswordEntry()
	pass.SetText(config.Password())
	interval := widget.NewEntry()
	interval.SetText(strconv.Itoa(current.IntervalMinutes))

	form := widget.NewForm(
		widget.NewFormItem("Broker (host)", host),
		widget.NewFormItem("Porta", port),
		widget.NewFormItem("Usuário", user),
		widget.NewFormItem("Senha", pass),
		widget.NewFormItem("Intervalo (min)", interval),
	)
	form.OnSubmit = func() {
		p, _ := strconv.Atoi(port.Text)
		iv, _ := strconv.Atoi(interval.Text)
		if iv < 1 {
			iv = 5
		}
		s := config.Settings{Host: host.Text, Port: p, Username: user.Text, IntervalMinutes: iv}
		onSave(s, pass.Text)
		w.Close()
	}
	form.SubmitText = "Salvar"

	w.SetContent(container.NewVBox(form))
	w.Resize(fyne.NewSize(420, 320))
	w.Show()
}
