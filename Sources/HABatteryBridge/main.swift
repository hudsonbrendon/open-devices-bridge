import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar agent: no Dock icon by default (also enforced via LSUIElement).
app.setActivationPolicy(.accessory)
app.run()
