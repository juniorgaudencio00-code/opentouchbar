import AppKit

// Barra virtual na tela — NSPanel flutuante, não-ativante, arrastável.
// Replica a Touch Bar em qualquer Mac (funciona onde não há hardware).

final class VirtualBarWindow: NSPanel {
    private var buttons: [ButtonConfig] = []
    private let dispatcher: ButtonDispatcher

    init(config: OTBConfig, engine: ActionEngine) {
        self.dispatcher = ButtonDispatcher(engine: engine)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92)
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.becomesKeyOnlyIfNeeded = true
        rebuild(with: config)
        // posição inicial: topo centrado
        if let screen = NSScreen.main {
            let f = screen.frame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - 96))
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func showAndCenter() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    func rebuild(with config: OTBConfig) {
        buttons = config.buttons
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        for button in config.buttons {
            let b = BarButton(config: button)
            b.onPress = { [weak self] label in
                Task { await self?.dispatcher.press(label, source: "button") }
            }
            stack.addArrangedSubview(b)
        }
        if config.buttons.isEmpty {
            let hint = NSTextField(labelWithString: "OpentouchBar — sem botões no config.toml")
            hint.textColor = .secondaryLabelColor
            hint.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(hint)
        }
        contentView = stack
        // ajusta o frame ao conteúdo mantendo o topo
        let top = (screen.map { $0.frame.maxY - 96 }) ?? (frame.maxY)
        let newSize = stack.fittingSize
        let origin = NSPoint(x: (NSScreen.main?.frame.midX ?? 0) - newSize.width / 2, y: top - newSize.height)
        setFrame(NSRect(origin: origin, size: newSize), display: true)
    }
}

// Botão da barra: emoji + label, hover highlight, clique despacha.
final class BarButton: NSControl {
    var onPress: ((String) -> Void)?
    private let config: ButtonConfig
    private let labelField = NSTextField(labelWithString: "")

    init(config: ButtonConfig) {
        self.config = config
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 44))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor

        labelField.stringValue = "\(config.emoji)  \(config.label)"
        labelField.font = .systemFont(ofSize: 13, weight: .medium)
        labelField.textColor = .white
        labelField.isEditable = false
        labelField.isBordered = false
        labelField.drawsBackground = false
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)
        NSLayoutConstraint.activate([
            labelField.centerXAnchor.constraint(equalTo: centerXAnchor),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            heightAnchor.constraint(equalToConstant: 44),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor }
    @objc private func clicked() { onPress?(config.label) }
}
