import AppKit

// Ponto de entrada (main.swift — top-level code).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // app de barra de menu: sem ícone no Dock
app.run()
