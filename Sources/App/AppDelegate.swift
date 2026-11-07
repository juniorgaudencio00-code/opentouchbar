import AppKit
import ServiceManagement

// OpentouchBar — alternativa aberta ao BetterTouchTool.
// App de barra de menu: motor de actions + servidor MCP + Touch Bar (hardware e virtual).

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var configStore: ConfigStore?
    var engine: ActionEngine?
    var virtualBar: VirtualBarWindow?
    var mcpServer: MCPServer?
    var hotkeyEngine = HotkeyEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "⚡️"
        statusItem.button?.toolTip = "OpentouchBar"
        rebuildMenu()

        do {
            let store = try ConfigStore()
            configStore = store
            let eng = ActionEngine()
            eng.currentConfig = store.current
            engine = eng

            let bar = VirtualBarWindow(config: store.current, engine: eng)
            virtualBar = bar

            HardwareTBProvider.shared.configure(
                buttons: store.current.buttons,
                dispatcher: eng.dispatcher
            )
            bar.touchBar = HardwareTBProvider.shared.makeTouchBar()

            hotkeyEngine.install(triggers: store.current.triggers, engine: eng)

            let server = MCPServer(engine: eng, configStore: store)
            mcpServer = server
            try server.start()

            store.onChange = { [weak self] cfg in
                guard let self = self, let eng = self.engine else { return }
                eng.currentConfig = cfg
                self.virtualBar?.rebuild(with: cfg)
                HardwareTBProvider.shared.configure(buttons: cfg.buttons, dispatcher: eng.dispatcher)
                self.virtualBar?.touchBar = HardwareTBProvider.shared.makeTouchBar()
                self.hotkeyEngine.install(triggers: cfg.triggers, engine: eng)
                self.mcpServer?.reloadConfig(cfg)
                self.rebuildMenu()
            }
        } catch {
            NSLog("OpentouchBar bootstrap falhou: \(error)")
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let barTitle = (virtualBar?.isVisible == true) ? "Esconder barra virtual" : "Mostrar barra virtual"
        menu.addItem(withTitle: barTitle, action: #selector(toggleBar), keyEquivalent: "")

        let configItem = menu.addItem(withTitle: "Editar config.toml", action: #selector(editConfig), keyEquivalent: ",")
        configItem.keyEquivalentModifierMask = [.command]

        let loginTitle = (SMAppService.mainApp.status == .enabled) ? "✓ Iniciar com o login" : "Iniciar com o login"
        menu.addItem(withTitle: loginTitle, action: #selector(toggleLogin), keyEquivalent: "")

        menu.addItem(.separator())
        if let cfg = configStore?.current, !cfg.triggers.isEmpty {
            let header = menu.addItem(withTitle: "Triggers:", action: nil, keyEquivalent: "")
            header.isEnabled = false
            for trigger in cfg.triggers {
                let t = menu.addItem(withTitle: "  ⌨️ \(trigger.hotkey) → \(trigger.action.kind.rawValue)", action: nil, keyEquivalent: "")
                t.isEnabled = false
            }
            menu.addItem(.separator())
        }

        let serverState = (mcpServer?.isRunning == true) ? "✅" : "⛔️"
        let srv = menu.addItem(withTitle: "Servidor MCP: \(serverState) :\(configStore?.current.server.port ?? 0)", action: nil, keyEquivalent: "")
        srv.isEnabled = false

        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do OpentouchBar", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc func toggleBar() {
        guard let bar = virtualBar else { return }
        bar.isVisible ? bar.orderOut(nil) : bar.showAndCenter()
        rebuildMenu()
    }

    @objc func editConfig() {
        guard let path = configStore?.path else { return }
        NSWorkspace.shared.open(NSURL(fileURLWithPath: path) as URL)
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("OpentouchBar: toggle login falhou: \(error)")
        }
        rebuildMenu()
    }

    @objc func quit() {
        hotkeyEngine.uninstall()
        mcpServer?.stop()
        NSApp.terminate(nil)
    }
}
