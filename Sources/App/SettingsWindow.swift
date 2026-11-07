import SwiftUI
import AppKit

// Editor visual mínimo — lista os botões, adiciona/remove, salva no TOML.
// O save passa pelo MESMO arquivo que agentes editam via MCP: sem estado paralelo.

struct EditorButtonRow: Identifiable {
    var id = UUID()
    var emoji: String
    var label: String
    var kind: String
    var payload: String
}

struct EditorView: View {
    @State var rows: [EditorButtonRow]
    @State var message: String = ""
    var onSave: ([EditorButtonRow]) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Botões da barra").font(.headline)
                Spacer()
                Button("+") {
                    rows.append(EditorButtonRow(emoji: "⚡️", label: "Novo", kind: "shell", payload: "echo novo"))
                }
                Button("−") {
                    if !rows.isEmpty { rows.removeLast() }
                }
            }
            if rows.isEmpty {
                Text("Nenhum botão — adicione com +").foregroundColor(.secondary)
            }
            ForEach($rows) { $row in
                HStack(spacing: 6) {
                    TextField("⚡️", text: $row.emoji)
                        .frame(width: 36)
                        .multilineTextAlignment(.center)
                    TextField("Nome", text: $row.label)
                        .frame(width: 110)
                    Picker("", selection: $row.kind) {
                        Text("shell").tag("shell")
                        Text("applescript").tag("applescript")
                        Text("js").tag("js")
                        Text("url").tag("url")
                    }
                    .frame(width: 105)
                    TextField("payload", text: $row.payload)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Divider()
            HStack {
                Text(message).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Salvar") {
                    onSave(rows)
                    message = "salvo — barra recarregada (\(Date().formatted(date: .omitted, time: .shortened)))"
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640)
    }
}

final class SettingsWindowController {
    var window: NSWindow?
    weak var configStore: ConfigStore?
    weak var engine: ActionEngine?

    init(configStore: ConfigStore, engine: ActionEngine) {
        self.configStore = configStore
        self.engine = engine
    }

    func show() {
        if window == nil {
            makeWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() {
        guard let store = configStore, let engine = engine,
              let cfg = engine.currentConfig else { return }
        let rows = cfg.buttons.map {
            EditorButtonRow(emoji: $0.emoji, label: $0.label, kind: $0.action.kind.rawValue, payload: $0.action.payload)
        }
        let view = EditorView(rows: rows) { [weak self] newRows in
            guard let self = self, let store = self.configStore, let engine = self.engine else { return }
            var cfg = engine.currentConfig ?? OTBConfig()
            cfg.buttons = newRows.compactMap { row in
                guard let kind = ActionKind(rawValue: row.kind), !row.label.isEmpty else { return nil }
                return ButtonConfig(label: row.label, emoji: row.emoji.isEmpty ? "⚡️" : row.emoji, color: nil,
                                    action: ActionConfig(kind: kind, payload: row.payload))
            }
            do {
                try store.save(cfg)
            } catch {
                NSLog("OpentouchBar: save do editor falhou: \(error)")
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "OpentouchBar — editor"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window
    }
}
