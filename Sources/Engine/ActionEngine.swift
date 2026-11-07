import Foundation

// O motor: valida a action, injeta variáveis {{nome}}, executa e loga.

final class ActionEngine {
    let runner = ActionRunner.shared
    let variables: VariablesStore
    /// config vigente (atualizada pelo ConfigStore.onChange)
    var currentConfig: OTBConfig?
    /// press_button reusa o mesmo caminho do clique
    lazy var dispatcher = ButtonDispatcher(engine: self)

    init(variables: VariablesStore = VariablesStore()) {
        self.variables = variables
    }

    /// Executa uma action genérica (MCP tools, triggers).
    func run(_ action: ActionConfig, source: String) async -> ActionResult {
        do {
            let result = try await runner.run(action, variables: variables.all())
            ExecutionLog.shared.record(source: source, kind: action.kind.rawValue, result: result)
            return result
        } catch {
            let result = ActionResult(output: "erro: \(error)", exitCode: -1, isError: true, durationMs: 0)
            ExecutionLog.shared.record(source: source, kind: action.kind.rawValue, result: result)
            return result
        }
    }
}
