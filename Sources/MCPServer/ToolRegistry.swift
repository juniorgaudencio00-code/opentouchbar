import Foundation
import AppKit

// Registry das tools MCP v1 — definição (name/description/inputSchema) + dispatch.
// Cada tool é uma função async (arguments) -> String (texto de resposta).

struct ToolDefinition {
    var name: String
    var description: String
    var inputSchema: [String: JSONValue]
    var handler: ([String: JSONValue]) async throws -> String
}

final class ToolRegistry {
    let engine: ActionEngine
    let configStore: ConfigStore

    init(engine: ActionEngine, configStore: ConfigStore) {
        self.engine = engine
        self.configStore = configStore
    }

    private func str(_ args: [String: JSONValue], _ key: String) throws -> String {
        guard let v = args[key]?.stringValue else {
            throw MCPToolError.missingParam(key)
        }
        return v
    }

    var definitions: [ToolDefinition] {
        [
            ToolDefinition(
                name: "run_shell",
                description: "Executa um comando shell (bash) no Mac do dono e retorna stdout+stderr. Timeout de 30s.",
                inputSchema: obj(["command": strProp("comando a executar")]),
                handler: { [engine] args in
                    let cmd = try self.str(args, "command")
                    let action = ActionConfig(kind: .shell, payload: cmd)
                    let result = await engine.run(action, source: "mcp:run_shell")
                    return result.output
                }
            ),
            ToolDefinition(
                name: "run_applescript",
                description: "Executa AppleScript (osascript). Útil para controlar apps, diálogos, automação de UI.",
                inputSchema: obj(["source": strProp("código AppleScript")]),
                handler: { [engine] args in
                    let src = try self.str(args, "source")
                    let result = await engine.run(ActionConfig(kind: .applescript, payload: src), source: "mcp:run_applescript")
                    return result.output
                }
            ),
            ToolDefinition(
                name: "run_js",
                description: "Executa JavaScript (JavaScriptCore). console.log() captura saída; valor da última expressão é retornado.",
                inputSchema: obj(["source": strProp("código JavaScript")]),
                handler: { [engine] args in
                    let src = try self.str(args, "source")
                    let result = await engine.run(ActionConfig(kind: .js, payload: src), source: "mcp:run_js")
                    return result.output
                }
            ),
            ToolDefinition(
                name: "get_variable",
                description: "Lê uma variável nomeada (usável nas actions como {{nome}}).",
                inputSchema: obj(["name": strProp("nome da variável")]),
                handler: { [engine] args in
                    let name = try self.str(args, "name")
                    return engine.variables.get(name) ?? ""
                }
            ),
            ToolDefinition(
                name: "set_variable",
                description: "Escreve uma variável nomeada (persistida em JSON).",
                inputSchema: obj([
                    "name": strProp("nome da variável"),
                    "value": strProp("valor"),
                ]),
                handler: { [engine] args in
                    let name = try self.str(args, "name")
                    let value = args["value"]?.stringValue ?? ""
                    engine.variables.set(name, value)
                    return "ok: \(name)"
                }
            ),
            ToolDefinition(
                name: "get_clipboard",
                description: "Lê o texto da área de transferência.",
                inputSchema: obj([:]),
                handler: { _ in
                    NSPasteboard.general.string(forType: .string) ?? ""
                }
            ),
            ToolDefinition(
                name: "set_clipboard",
                description: "Escreve texto na área de transferência.",
                inputSchema: obj(["text": strProp("texto")]),
                handler: { args in
                    let text = args["text"]?.stringValue ?? ""
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    return "ok (\(text.count) chars)"
                }
            ),
            ToolDefinition(
                name: "list_directory",
                description: "Lista o conteúdo de um diretório com tipos e tamanhos.",
                inputSchema: obj(["path": strProp("caminho do diretório (aceita ~)")]),
                handler: { args in
                    let raw = try self.str(args, "path")
                    let path = NSString(string: raw).expandingTildeInPath
                    let items = try FileManager.default.contentsOfDirectory(atPath: path)
                    return items.sorted().joined(separator: "\n")
                }
            ),
            ToolDefinition(
                name: "create_file",
                description: "Cria/sobrescreve um arquivo com conteúdo (atomic). É assim que agents editam o config.toml da barra.",
                inputSchema: obj([
                    "path": strProp("caminho do arquivo (aceita ~)"),
                    "content": strProp("conteúdo"),
                ]),
                handler: { args in
                    let raw = try self.str(args, "path")
                    let path = NSString(string: raw).expandingTildeInPath
                    let content = args["content"]?.stringValue ?? ""
                    let dir = (path as NSString).deletingLastPathComponent
                    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                    return "ok: \(path) (\(content.count) bytes)"
                }
            ),
            ToolDefinition(
                name: "get_execution_log",
                description: "Últimas execuções (source, tipo, duração, rc, saída).",
                inputSchema: obj([
                    "limit": JSONValue.number(20),
                    "errors_only": .bool(false),
                ]),
                handler: { args in
                    let limit = Int(args["limit"]?.numberValue ?? 20) ?? 20
                    let errorsOnly = args["errors_only"]?.boolValue ?? false
                    return ExecutionLog.shared.asText(limit: limit, errorsOnly: errorsOnly)
                }
            ),
            ToolDefinition(
                name: "list_buttons",
                description: "Lista os botões atuais da barra (label, emoji, tipo de action).",
                inputSchema: obj([:]),
                handler: { [engine] _ in
                    guard let cfg = engine.currentConfig else { return "config não carregada" }
                    guard !cfg.buttons.isEmpty else { return "nenhum botão" }
                    return cfg.buttons.map { "- \($0.emoji) \($0.label) → \($0.action.kind.rawValue)" }.joined(separator: "\n")
                }
            ),
            ToolDefinition(
                name: "press_button",
                description: "Aperta um botão da barra pelo label — mesmo caminho do clique humano.",
                inputSchema: obj(["label": strProp("label do botão")]),
                handler: { [engine] args in
                    let label = try self.str(args, "label")
                    return await engine.dispatcher.press(label, source: "mcp")
                }
            ),
        ]
    }

    func dispatch(_ name: String, args: [String: JSONValue]) async -> (text: String, isError: Bool) {
        guard let tool = definitions.first(where: { $0.name == name }) else {
            return ("tool desconhecida: \(name)", true)
        }
        do {
            let output = try await tool.handler(args)
            return (output, false)
        } catch {
            return ("erro: \(error)", true)
        }
    }

    // MARK: - schemas

    private enum MCPToolError: Error, CustomStringConvertible {
        case missingParam(String)
        var description: String { "parâmetro ausente" }
    }

    private func obj(_ props: [String: JSONValue]) -> [String: JSONValue] {
        ["type": .string("object"), "properties": .object(props)]
    }

    private func strProp(_ desc: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(desc)])
    }
}

extension JSONValue {
    var numberValue: Double? { if case .number(let d) = self { return d }; return nil }
}
