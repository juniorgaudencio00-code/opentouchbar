import Foundation

// JSON-RPC 2.0 + valor JSON dinâmico (o MCP carrega payloads de shape variável).

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let d = try? container.decode(Double.self) { self = .number(d); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "JSON inválido")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    /// Busca por caminho "a.b.c" em objetos aninhados.
    subscript(path: String) -> JSONValue? {
        var cur: JSONValue = self
        for key in path.split(separator: ".").map(String.init) {
            guard case .object(let o) = cur, let next = o[key] else { return nil }
            cur = next
        }
        return cur
    }
}

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

struct JSONRPCResponse: Codable {
    let jsonrpc = "2.0"
    let id: JSONValue
    let result: JSONValue?
    let error: JSONRPCError?

    static func ok(id: JSONValue, _ result: JSONValue) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: result, error: nil)
    }
    static func err(id: JSONValue, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: code, message: message))
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

enum JSONRPCErrorCodes {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}
