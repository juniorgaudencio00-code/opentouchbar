import Foundation

// Variáveis nomeadas — o estado que agents leem/escrevem via MCP e as
// actions consumem com {{variavel}}. Persistidas em JSON.

final class VariablesStore {
    private var values: [String: String] = [:]
    private let queue = DispatchQueue(label: "otb.variables")
    private let path: String

    init(path: String = NSString(string: "~/.config/opentouchbar/variables.json").expandingTildeInPath) {
        self.path = path
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            values = decoded
        }
    }

    func get(_ key: String) -> String? {
        queue.sync { values[key] }
    }

    func set(_ key: String, _ value: String) {
        queue.sync {
            values[key] = value
            persistLocked()
        }
    }

    func all() -> [String: String] {
        queue.sync { values }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
