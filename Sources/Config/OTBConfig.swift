import Foundation

// Modelo de config do OpentouchBar — decodificado do TOML.

enum ActionKind: String {
    case shell
    case applescript
    case js
    case url
}

struct ActionConfig: Equatable {
    var kind: ActionKind
    var payload: String  // command | source | url

    static func from(_ table: [String: TOMLValue]) -> ActionConfig? {
        guard let type = table["type"]?.stringValue else { return nil }
        let kind = ActionKind(rawValue: type) ?? .shell
        let payload: String
        switch kind {
        case .shell: payload = table["command"]?.stringValue ?? ""
        case .applescript: payload = table["source"]?.stringValue ?? (table["file"]?.stringValue.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? "")
        case .js: payload = table["source"]?.stringValue ?? ""
        case .url: payload = table["url"]?.stringValue ?? ""
        }
        return ActionConfig(kind: kind, payload: payload)
    }
}

struct ButtonConfig: Equatable {
    var label: String
    var emoji: String
    var color: String?
    var action: ActionConfig
}

struct TriggerConfig: Equatable {
    var hotkey: String
    var action: ActionConfig
}

struct ServerConfig: Equatable {
    var port: Int
    var token: String
}

struct OTBConfig: Equatable {
    var server = ServerConfig(port: 64833, token: "")
    var buttons: [ButtonConfig] = []
    var triggers: [TriggerConfig] = []

    static func from(_ root: [String: TOMLValue]) throws -> OTBConfig {
        var cfg = OTBConfig()

        if let server = root["server"]?.tableValue {
            if let p = server["port"]?.intValue { cfg.server.port = p }
            if let t = server["token"]?.stringValue { cfg.server.token = t }
        }

        if let buttons = root["buttons"]?.arrayValue {
            for case .table(let t) in buttons {
                guard let label = t["label"]?.stringValue else { continue }
                let action = ActionConfig.from(t["action"]?.tableValue ?? [:])
                guard let action = action, !action.payload.isEmpty else { continue }
                cfg.buttons.append(ButtonConfig(
                    label: label,
                    emoji: t["emoji"]?.stringValue ?? "⚡️",
                    color: t["color"]?.stringValue,
                    action: action
                ))
            }
        }

        if let triggers = root["triggers"]?.arrayValue {
            for case .table(let t) in triggers {
                guard let hotkey = t["hotkey"]?.stringValue,
                      let action = ActionConfig.from(t["action"]?.tableValue ?? [:]),
                      !action.payload.isEmpty else { continue }
                cfg.triggers.append(TriggerConfig(hotkey: hotkey, action: action))
            }
        }

        return cfg
    }
}
