import AppKit

/// Marca de arranque, para poder medir cuánto tarda la isla en estar lista.
let launchStart = Date()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
