import Foundation

// Despacha o botão apertado — ÚNICO caminho para clique na barra virtual,
// toque na Touch Bar hardware e a tool MCP press_button.

final class ButtonDispatcher {
    let engine: ActionEngine

    init(engine: ActionEngine) {
        self.engine = engine
    }

    /// Executa a action do botão pelo label. Retorna o resultado em texto.
    /// (o log fica por conta do engine.run — nada de log duplo)
    @discardableResult
    func press(_ label: String, source: String = "button") async -> String {
        guard let button = engine.currentConfig?.buttons.first(where: { $0.label == label }) else {
            return "botão não encontrado: \(label)"
        }
        return await engine.run(button.action, source: "\(source):\(label)").output
    }
}
