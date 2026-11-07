import XCTest
@testable import OpentouchBar

final class TOMLTests: XCTestCase {
    func testTabelasEValores() throws {
        let toml = """
        [server]
        port = 64833
        token = "abc"

        [[buttons]]
        label = "Deploy"
        emoji = "🚀"

        [buttons.action]
        type = "shell"
        command = "echo oi"
        """
        let root = try TOML.parse(toml)
        XCTAssertEqual(root["server"]?.tableValue?["port"]?.intValue, 64833)
        XCTAssertEqual(root["server"]?.tableValue?["token"]?.stringValue, "abc")
        let button = root["buttons"]?.arrayValue?.first?.tableValue
        XCTAssertEqual(button?["label"]?.stringValue, "Deploy")
        XCTAssertEqual(button?["action"]?.tableValue?["command"]?.stringValue, "echo oi")
    }

    func testArrayDeTabelasMultiplas() throws {
        let toml = """
        [[buttons]]
        label = "A"

        [[buttons]]
        label = "B"
        """
        let root = try TOML.parse(toml)
        XCTAssertEqual(root["buttons"]?.arrayValue?.count, 2)
        let b = root["buttons"]?.arrayValue?.last?.tableValue?["label"]?.stringValue
        XCTAssertEqual(b, "B")
    }

    func testChaveComPontos() throws {
        let toml = """
        [[buttons]]
        label = "X"
        action.type = "url"
        """
        let root = try TOML.parse(toml)
        let button = root["buttons"]?.arrayValue?.first?.tableValue
        XCTAssertEqual(button?["action"]?.tableValue?["type"]?.stringValue, "url")
    }

    func testComentariosEStrings() throws {
        let toml = """
        # comentário
        [server] # tabela
        token = "com # hash e \\"aspas\\""
        port = 1234
        """
        let root = try TOML.parse(toml)
        XCTAssertEqual(root["server"]?.tableValue?["token"]?.stringValue, "com # hash e \"aspas\"")
        XCTAssertEqual(root["server"]?.tableValue?["port"]?.intValue, 1234)
    }

    func testDecodificaConfigCompleta() throws {
        let toml = """
        [server]
        port = 7000
        token = "tok"

        [[buttons]]
        label = "Ping"
        emoji = "📡"
        [buttons.action]
        type = "shell"
        command = "echo ok"

        [[buttons]]
        label = "Site"
        emoji = "🌐"
        [buttons.action]
        type = "url"
        url = "https://exemplo.com"

        [[triggers]]
        hotkey = "cmd+shift+o"
        [triggers.action]
        type = "shell"
        command = "true"
        """
        let cfg = try OTBConfig.from(try TOML.parse(toml))
        XCTAssertEqual(cfg.server.port, 7000)
        XCTAssertEqual(cfg.buttons.count, 2)
        XCTAssertEqual(cfg.buttons[0].action.kind, .shell)
        XCTAssertEqual(cfg.buttons[1].action.kind, .url)
        XCTAssertEqual(cfg.triggers.count, 1)
        XCTAssertEqual(cfg.triggers[0].hotkey, "cmd+shift+o")
    }

    func testValorAusenteNaoQuebra() throws {
        let cfg = try OTBConfig.from(try TOML.parse(""))
        XCTAssertEqual(cfg.server.port, 64833)  // default
        XCTAssertEqual(cfg.buttons.count, 0)
    }
}
