import XCTest
@testable import OpentouchBar

final class TOMLWriterTests: XCTestCase {
    func testRoundTrip() throws {
        var cfg = OTBConfig()
        cfg.server = ServerConfig(port: 7001, token: "tok\"com\\escape\"")
        cfg.buttons = [
            ButtonConfig(label: "Deploy", emoji: "🚀", color: nil,
                         action: ActionConfig(kind: .shell, payload: "./deploy.sh --flag")),
            ButtonConfig(label: "Site", emoji: "🌐", color: nil,
                         action: ActionConfig(kind: .url, payload: "https://exemplo.com")),
            ButtonConfig(label: "Alerta", emoji: "🔔", color: nil,
                         action: ActionConfig(kind: .applescript, payload: "display dialog \"oi\"")),
            ButtonConfig(label: "Calc", emoji: "🧮", color: nil,
                         action: ActionConfig(kind: .js, payload: "1+1")),
        ]
        cfg.triggers = [TriggerConfig(hotkey: "cmd+shift+t",
                                      action: ActionConfig(kind: .shell, payload: "true"))]

        let text = cfg.toTOML()
        let reparsed = try OTBConfig.from(try TOML.parse(text))
        XCTAssertEqual(reparsed, cfg)  // Equatable cobre tudo
    }

    func testWriterEscapaCaracteresPerigosos() throws {
        var cfg = OTBConfig()
        cfg.buttons = [ButtonConfig(label: "com \"aspas\" e \\ barra", emoji: "❗️", color: nil,
                                    action: ActionConfig(kind: .shell, payload: "echo \"linha1\"\necho linha2"))]
        let text = cfg.toTOML()
        let reparsed = try OTBConfig.from(try TOML.parse(text))
        XCTAssertEqual(reparsed.buttons[0].label, "com \"aspas\" e \\ barra")
        XCTAssertEqual(reparsed.buttons[0].action.payload, "echo \"linha1\"\necho linha2")
    }
}
