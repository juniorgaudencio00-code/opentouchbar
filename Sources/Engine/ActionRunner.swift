import Foundation
import AppKit
import JavaScriptCore

// Executa actions: shell (Process + timeout), applescript (osascript),
// js (JavaScriptCore in-process), url (NSWorkspace).

struct ActionResult {
    var output: String
    var exitCode: Int32
    var isError: Bool
    var durationMs: Int
}

enum ActionError: Error, CustomStringConvertible {
    case emptyPayload
    case timeout(Int)
    case jsError(String)
    var description: String {
        switch self {
        case .emptyPayload: return "action sem payload"
        case .timeout(let s): return "timeout após \(s)s"
        case .jsError(let m): return "JS: \(m)"
        }
    }
}

final class ActionRunner {
    static let shared = ActionRunner()
    /// timeout padrão por action (s) — o TOML pode sobrescrever por action no futuro
    var defaultTimeout: Int = 30

    /// Executa uma action. Roda em qualquer queue; captura stdout+stderr.
    func run(_ action: ActionConfig, variables: [String: String] = [:]) async throws -> ActionResult {
        guard !action.payload.isEmpty else { throw ActionError.emptyPayload }
        let start = Date()
        let rendered = render(action.payload, variables: variables)
        switch action.kind {
        case .shell:
            let out = try await runProcess("/bin/bash", args: ["-c", rendered], timeout: defaultTimeout)
            return ActionResult(output: out.output, exitCode: out.exitCode, isError: out.exitCode != 0, durationMs: elapsed(start))
        case .applescript:
            let out = try await runProcess("/usr/bin/osascript", args: ["-e", rendered], timeout: defaultTimeout)
            return ActionResult(output: out.output, exitCode: out.exitCode, isError: out.exitCode != 0, durationMs: elapsed(start))
        case .js:
            let output = try runJS(rendered)
            return ActionResult(output: output, exitCode: 0, isError: false, durationMs: elapsed(start))
        case .url:
            guard let url = URL(string: rendered) else {
                return ActionResult(output: "URL inválida: \(rendered)", exitCode: 1, isError: true, durationMs: elapsed(start))
            }
            await MainActor.run { NSWorkspace.shared.open(url) }
            return ActionResult(output: "aberto: \(rendered)", exitCode: 0, isError: false, durationMs: elapsed(start))
        }
    }

    private func elapsed(_ start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

    /// Substitui {{variavel}} pelo valor.
    func render(_ payload: String, variables: [String: String]) -> String {
        guard !variables.isEmpty else { return payload }
        var out = payload
        for (k, v) in variables {
            out = out.replacingOccurrences(of: "{{\(k)}}", with: v)
        }
        return out
    }

    // MARK: - Process com timeout

    func runProcess(_ launchPath: String, args: [String], timeout: Int) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                do { try process.run() } catch {
                    cont.resume(returning: (output: "falha ao iniciar: \(error)", exitCode: 127))
                    return
                }

                let exited = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    exited.signal()
                }
                let timedOut = exited.wait(timeout: .now() + .seconds(timeout)) == .timedOut
                if timedOut {
                    process.terminate()
                    _ = exited.wait(timeout: .now() + 3)
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                // processo saiu (ou morto): pipes fecham, leitura até o fim é rápida
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: outData, encoding: .utf8) ?? ""
                let errText = String(data: errData, encoding: .utf8) ?? ""
                if timedOut {
                    cont.resume(returning: (output: text + errText + "\n[OpentouchBar] timeout de \(timeout)s", exitCode: 124))
                } else {
                    cont.resume(returning: (output: text + (errText.isEmpty ? "" : "\n" + errText), exitCode: process.terminationStatus))
                }
            }
        }
    }

    // MARK: - JavaScript (JavaScriptCore, in-process)

    func runJS(_ source: String) throws -> String {
        guard let ctx = JSContext() else { throw ActionError.jsError("JSContext indisponível") }
        var captured: String = ""
        ctx.exceptionHandler = { _, exc in
            let msg = exc?.toString() ?? "erro desconhecido"
            if captured.isEmpty { captured = msg }
        }
        // ponte mínima: console.log capturado
        ctx.evaluateScript("""
        var console = { log: function() {
            var parts = [];
            for (var i = 0; i < arguments.length; i++) parts.push(String(arguments[i]));
            __otbLog(parts.join(' '));
        } };
        """)
        let logHandler: @convention(block) (String) -> Void = { msg in
            captured += (captured.isEmpty ? "" : "\n") + msg
        }
        ctx.setObject(logHandler, forKeyedSubscript: "__otbLog" as NSString)
        ctx.evaluateScript(source)
        if let exc = ctx.exception {
            throw ActionError.jsError(captured.isEmpty ? (exc.toString() ?? "erro") : captured)
        }
        if let last = ctx.evaluateScript(source)?.toString(), !last.isEmpty, captured.isEmpty {
            captured = last  // valor da última expressão, se não houve log
        }
        return captured
    }
}
