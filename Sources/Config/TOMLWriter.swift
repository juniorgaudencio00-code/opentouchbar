import Foundation

// TOMLWriter — serializa a config de volta pra texto. O editor visual escreve
// o MESMO arquivo que agentes e humanos editam: uma fonte de verdade só.

extension OTBConfig {
    func toTOML() -> String {
        var out = "# OpentouchBar — gerado pelo editor visual (editável à mão também)\n\n"
        out += "[server]\nport = \(server.port)\ntoken = \"\(Self.escape(server.token))\"\n"

        if !buttons.isEmpty {
            out += "\n"
            for b in buttons {
                out += "[[buttons]]\n"
                out += "label = \"\(Self.escape(b.label))\"\n"
                out += "emoji = \"\(Self.escape(b.emoji))\"\n"
                out += "[buttons.action]\n"
                out += "type = \"\(b.action.kind.rawValue)\"\n"
                switch b.action.kind {
                case .shell: out += "command = \"\(Self.escape(b.action.payload))\"\n"
                case .applescript, .js: out += "source = \"\(Self.escape(b.action.payload))\"\n"
                case .url: out += "url = \"\(Self.escape(b.action.payload))\"\n"
                }
                out += "\n"
            }
        }

        if !triggers.isEmpty {
            for t in triggers {
                out += "[[triggers]]\n"
                out += "hotkey = \"\(Self.escape(t.hotkey))\"\n"
                out += "[triggers.action]\n"
                out += "type = \"\(t.action.kind.rawValue)\"\n"
                switch t.action.kind {
                case .shell: out += "command = \"\(Self.escape(t.action.payload))\"\n"
                case .applescript, .js: out += "source = \"\(Self.escape(t.action.payload))\"\n"
                case .url: out += "url = \"\(Self.escape(t.action.payload))\"\n"
                }
                out += "\n"
            }
        }
        return out
    }

    /// Escapa para basic string TOML: \\ \" \n \t \r
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
