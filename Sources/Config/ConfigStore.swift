import Foundation

// Carrega, cria e observa a config (~/.config/opentouchbar/config.toml).
// Hot-reload: DispatchSource no fd do arquivo com debounce.

final class ConfigStore {
    private(set) var current: OTBConfig
    let path: String
    var onChange: ((OTBConfig) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?

    static var defaultPath: String {
        let dir = NSString(string: "~/.config/opentouchbar").expandingTildeInPath
        return dir + "/config.toml"
    }

    init(path: String = ConfigStore.defaultPath) throws {
        self.path = path
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: path) {
            let token = Self.generateToken()
            try Self.defaultConfig(token: token).write(toFile: path, atomically: true, encoding: .utf8)
        }
        self.current = try Self.readConfig(path: path)
        try persistTokenIfGenerated()
        startWatching()
    }

    static func readConfig(path: String) throws -> OTBConfig {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let toml = try TOML.parse(text)
        return try OTBConfig.from(toml)
    }

    /// Token vazio/"change-me" → gera, persiste no TOML e usa.
    private func persistTokenIfGenerated() throws {
        let needsToken = current.server.token.isEmpty || current.server.token == "change-me"
        guard needsToken else { return }
        let token = Self.generateToken()
        var text = try String(contentsOfFile: path, encoding: .utf8)
        if text.range(of: #"^token\s*=\s*".*"$"#, options: .regularExpression) != nil {
            if let range = text.range(of: #"(?m)^token\s*=\s*".*"$"#, options: .regularExpression) {
                text.replaceSubrange(range, with: "token = \"\(token)\"")
            }
        } else if text.range(of: #"(?m)^\[server\]"#, options: .regularExpression) != nil {
            text += "token = \"\(token)\"\n"
        } else {
            text += "\n[server]\nport = \(current.server.port)\ntoken = \"\(token)\"\n"
        }
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        current.server.token = token
    }

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func defaultConfig(token: String) -> String {
        """
        # OpentouchBar — config declarativa. Editar este arquivo atualiza a barra na hora.
        # Agentes: este arquivo É a API da barra. Botão novo = bloco novo [[buttons]].

        [server]
        port = 64833
        token = "\(token)"

        # action types: shell (command) | applescript (source) | js (source) | url (url)

        [[buttons]]
        label = "Ping"
        emoji = "📡"
        [buttons.action]
        type = "shell"
        command = "echo opentouchbar ok"

        [[buttons]]
        label = "GitHub"
        emoji = "🐙"
        [buttons.action]
        type = "url"
        url = "https://github.com"

        [[buttons]]
        label = "Dicionário"
        emoji = "📖"
        [buttons.action]
        type = "applescript"
        source = "display dialog \\"OpentouchBar no ar\\" buttons {\\"OK\\"}"
        """
    }

    // MARK: - Hot reload

    private func startWatching() {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let cfg = try? Self.readConfig(path: self.path) else { return }  // arquivo pela metade: ignora
            guard cfg != self.current else { return }
            self.current = cfg
            DispatchQueue.main.async { self.onChange?(cfg) }
        }
        reloadWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: item)
    }
}
