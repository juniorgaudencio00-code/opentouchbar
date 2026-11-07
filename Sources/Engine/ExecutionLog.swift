import Foundation

// Log de execução — ring buffer consultável via MCP (get_execution_log).

struct LogEntry: Codable, Equatable {
    var timestamp: Date
    var source: String      // "button:Deploy" | "mcp:run_shell" | "trigger:cmd+o"
    var kind: String        // shell | applescript | js | url
    var output: String
    var exitCode: Int32
    var isError: Bool
    var durationMs: Int
}

final class ExecutionLog {
    static let shared = ExecutionLog()
    private var entries: [LogEntry] = []
    private let queue = DispatchQueue(label: "otb.log")
    private let capacity = 200

    func record(source: String, kind: String, result: ActionResult) {
        queue.sync {
            entries.append(LogEntry(
                timestamp: Date(),
                source: source,
                kind: kind,
                output: String(result.output.prefix(2000)),
                exitCode: result.exitCode,
                isError: result.isError,
                durationMs: result.durationMs
            ))
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    func recent(_ limit: Int = 20, errorsOnly: Bool = false) -> [LogEntry] {
        queue.sync {
            let filtered = errorsOnly ? entries.filter(\.isError) : entries
            return Array(filtered.suffix(limit))
        }
    }

    func asText(limit: Int = 20, errorsOnly: Bool = false) -> String {
        let items = recent(limit, errorsOnly: errorsOnly)
        guard !items.isEmpty else { return "log vazio" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return items.map { e in
            let status = e.isError ? "❌" : "✅"
            return "\(df.string(from: e.timestamp)) \(status) [\(e.source)] \(e.kind) (\(e.durationMs)ms, rc=\(e.exitCode))\n  \(e.output.replacingOccurrences(of: "\n", with: "\n  "))"
        }.joined(separator: "\n")
    }
}
