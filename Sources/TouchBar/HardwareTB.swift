import AppKit

// Touch Bar de hardware (NSTouchBar) com os mesmos botões do TOML.
// Só ativa em Macs com barra física; a barra virtual cobre o resto.

final class HardwareTBProvider: NSObject, NSTouchBarDelegate {
    static let shared = HardwareTBProvider()
    private var buttons: [ButtonConfig] = []
    private var dispatcher: ButtonDispatcher?
    static let touchBarID = NSTouchBar.CustomizationIdentifier("app.opentouchbar.bar")
    static let itemBase = NSTouchBarItem.Identifier("app.opentouchbar.button.")

    func configure(buttons: [ButtonConfig], dispatcher: ButtonDispatcher) {
        self.buttons = buttons
        self.dispatcher = dispatcher
    }

    func makeTouchBar() -> NSTouchBar? {
        guard !buttons.isEmpty else { return nil }
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = Self.touchBarID
        bar.defaultItemIdentifiers = buttons.enumerated().map {
            NSTouchBarItem.Identifier(Self.itemBase.rawValue + String($0.offset))
        }
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier.rawValue.hasPrefix(Self.itemBase.rawValue),
              let index = Int(identifier.rawValue.dropFirst(Self.itemBase.rawValue.count)),
              index < buttons.count else { return nil }
        let button = buttons[index]
        let item = NSCustomTouchBarItem(identifier: identifier)
        let nsButton = NSButton(title: "\(button.emoji) \(button.label)", target: self, action: #selector(pressed(_:)))
        nsButton.bezelColor = NSColor.systemBlue
        nsButton.tag = index
        item.view = nsButton
        return item
    }

    @objc private func pressed(_ sender: NSButton) {
        guard sender.tag < buttons.count else { return }
        let label = buttons[sender.tag].label
        Task { await dispatcher?.press(label, source: "touchbar") }
    }
}
