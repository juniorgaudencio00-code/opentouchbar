import Foundation

// Despacha o botão apertado — ÚNICO caminho para clique na barra virtual,
// toque na Touch Bar hardware e a tool MCP press_button.

final class ButtonDispatcher {
    let engine: ActionEngine

    init(engine: ActionEngine) {
        self.engine = engine
    }

    /// Executa a action do botão pelo label. Retorna o resultado em texto.
    @discardableResult
    func press(_ label: String, source: String = "button") async -> String {
        guard let button = engine.currentConfig?.buttons.first(where: { $0.label == label }) else {
            return "botão não encontrado: \(label)"
        }
        do {
            let result = await engine.run(button.action, source: "\(source):\(label)")
            ExecutionLog.shared.record(source: "\(source):\(label)", kind: button.action.kind.rawValue, result: result)
            return result.output
        } catch {
            let result = ActionResult(output: "erro: \(error)", exitCode: -1, isError: true, durationMs: 0)
            ExecutionLog.shared.record(source: "\(source):\(label)", kind: button.action.kind.rawValue, result: result)
            return result.output
        }
    }
}
