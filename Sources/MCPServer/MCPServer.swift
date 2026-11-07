import Foundation
import Network

// Servidor MCP sobre HTTP (Streamable HTTP, JSON-RPC 2.0):
// POST /mcp com JSON-RPC; bearer token; resposta application/json.

final class MCPServer {
    private var listener: NWListener?
    private(set) var isRunning = false
    private var port: UInt16 = 64833
    private var token: String = ""
    private let queue = DispatchQueue(label: "otb.mcp.server")
    private let registry: ToolRegistry
    private let version = "0.1.0"
    private let protocolVersion = "2025-03-26"

    init(engine: ActionEngine, configStore: ConfigStore) {
        self.registry = ToolRegistry(engine: engine, configStore: configStore)
        port = UInt16(configStore.current.server.port)
        token = configStore.current.server.token
    }

    func reloadConfig(_ config: OTBConfig) {
        // mudança de porta/token exige restart; feito pelo AppDelegate se necessário
        port = UInt16(config.server.port)
        token = config.server.token
    }

    func start() throws {
        guard !isRunning else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.isRunning = true
            case .failed: self?.isRunning = false
            case .cancelled: self?.isRunning = false
            default: break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - conexão / HTTP

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let data = data { buf.append(data) }
            if let request = HTTPRequest.parse(buf) {
                let response = self.route(request)
                self.send(response: response, to: connection)
            } else if error == nil && !isComplete {
                self.receiveRequest(connection, buffer: buf)
            } else {
                // conexão fechada sem request completo: ignora
                connection.cancel()
            }
        }
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        // auth: Bearer token em toda rota
        guard request.header("authorization") == "Bearer \(token)" else {
            return HTTPResponse(status: 401, body: #"{"error":"unauthorized"}"#)
        }
        guard request.method == "POST", request.path == "/mcp" || request.path == "/" else {
            return HTTPResponse(status: 405, body: #"{"error":"use POST /mcp"}"#)
        }
        guard let data = request.bodyData else {
            return HTTPResponse(status: 400, body: #"{"error":"body vazio"}"#)
        }
        let decoder = JSONDecoder()
        guard let rpc = try? decoder.decode(JSONRPCRequest.self, from: data), rpc.jsonrpc == "2.0" else {
            return HTTPResponse(status: 200, body: encode(JSONRPCResponse.err(id: .null, code: JSONRPCErrorCodes.parseError, message: "JSON-RPC inválido")))
        }

        // notification (sem id): 202 vazio
        guard let id = rpc.id else {
            return HTTPResponse(status: 202, body: "")
        }

        let result: JSONRPCResponse
        switch rpc.method {
        case "initialize":
            let clientVersion = rpc.params?["protocolVersion"]?.stringValue ?? protocolVersion
            let resultJSON = JSONValue.object([
                "protocolVersion": .string(clientVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string("opentouchbar"),
                    "version": .string(version),
                ]),
            ])
            result = .ok(id: id, resultJSON)
        case "ping":
            result = .ok(id: id, .object([:]))
        case "tools/list":
            let tools = registry.definitions.map { tool in
                JSONValue.object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": .object(tool.inputSchema),
                ])
            }
            result = .ok(id: id, .object(["tools": .array(tools)]))
        case "tools/call":
            let name = rpc.params?["name"]?.stringValue ?? ""
            let args = rpc.params?["arguments"]?.objectValue ?? [:]
            // dispatch async seria melhor, mas MVP responde inline (tools são rápidas, timeout 30s)
            let semaphore = DispatchSemaphore(value: 0)
            __concurrentQueue.async {
                Task {
                    let (text, isError) = await self.registry.dispatch(name, args: args)
                    let response = JSONRPCResponse.ok(id: id, .object([
                        "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                        "isError": .bool(isError),
                    ]))
                    self.pendingResponse = response
                    semaphore.signal()
                }
            }
            semaphore.wait()
            guard let pending = pendingResponse else {
                result = .err(id: id, code: JSONRPCErrorCodes.internalError, message: "dispatch falhou")
                break
            }
            result = pending
        default:
            result = .err(id: id, code: JSONRPCErrorCodes.methodNotFound, message: "método desconhecido: \(rpc.method)")
        }
        return HTTPResponse(status: 200, body: encode(result))
    }

    private let __concurrentQueue = DispatchQueue(label: "otb.mcp.tools")
    private var pendingResponse: JSONRPCResponse?

    private func encode(_ response: JSONRPCResponse) -> String {
        guard let data = try? JSONEncoder().encode(response) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func send(response: HTTPResponse, to connection: NWConnection) {
        let head = "HTTP/1.1 \(response.status) \(response.reason)\r\nContent-Type: application/json\r\nContent-Length: \(response.body.utf8.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(Data(response.body.utf8))
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - HTTP mínimo

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: String

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var bodyData: Data? { body.data(using: .utf8) }

    /// Parse de request HTTP/1.1; retorna nil se incompleto.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let headEnd = text.range(of: "\r\n\r\n") else { return nil }
        let head = String(text[text.startIndex..<headEnd.lowerBound])
        let body = String(text[headEnd.upperBound...])
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard body.utf8.count >= contentLength else { return nil }
        let trimmedBody = String(body.prefix(contentLength))
        let path = parts[1].split(separator: "?").first.map(String.init) ?? parts[1]
        return HTTPRequest(method: parts[0], path: path, headers: headers, body: trimmedBody)
    }
}

struct HTTPResponse {
    var status: Int
    var body: String
    var reason: String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 405: return "Method Not Allowed"
        default: return "Error"
        }
    }
}
