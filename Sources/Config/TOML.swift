import Foundation

// Parser TOML de subconjunto — só o que o config do OpentouchBar usa:
// tabelas [a.b.c], array de tabelas [[a]], chave com pontos (a.b = v),
// valores: basic string, int, float, bool. Sem multiline strings.
//
// Design: todas as operações usam PATHS ABSOLUTOS sobre a árvore de valores.
// Elementos numéricos de um path indexam arrays (ex.: ["buttons", "0", "action"]).

enum TOMLValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case table([String: TOMLValue])
    case array([TOMLValue])

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int? { if case .int(let i) = self { return i }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [TOMLValue]? { if case .array(let a) = self { return a }; return nil }
    var tableValue: [String: TOMLValue]? { if case .table(let t) = self { return t }; return nil }
}

enum TOMLError: Error, CustomStringConvertible {
    case parse(String, line: Int)
    var description: String {
        if case .parse(let msg, let line) = self { return "TOML linha \(line): \(msg)" }
        return "erro TOML"
    }
}

enum TOML {

    // MARK: - Entrada

    static func parse(_ text: String) throws -> [String: TOMLValue] {
        var root: [String: TOMLValue] = [:]
        var currentPath: [String] = []

        for (idx, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let n = idx + 1
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            do {
                if line.hasPrefix("[[") {
                    guard line.hasSuffix("]]") else { throw TOMLError.parse("[[ sem ]]", line: n) }
                    let path = splitPath(String(line.dropFirst(2).dropLast(2)))
                    try appendArrayTable(&root, path: path)
                    let count = arrayCount(&root, path: path)
                    currentPath = path + [String(count - 1)]
                } else if line.hasPrefix("[") {
                    guard line.hasSuffix("]") else { throw TOMLError.parse("[ sem ]", line: n) }
                    let path = splitPath(String(line.dropFirst().dropLast()))
                    try ensurePath(&root, path: path)
                    currentPath = path
                } else if let eq = keyValueSplit(line) {
                    let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                    let raw = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    let value = try parseValue(raw, line: n)
                    try setValue(&root, path: currentPath + splitPath(key), value: value)
                } else {
                    throw TOMLError.parse("linha inválida: \(line.prefix(30))", line: n)
                }
            } catch let e as TOMLError { throw e }
            catch { throw TOMLError.parse("\(error)", line: n) }
        }
        return root
    }

    // MARK: - Navegação na árvore (arrays via elemento numérico do path)

    static func get(_ root: [String: TOMLValue], path: [String]) -> TOMLValue? {
        var cur: TOMLValue = .table(root)
        for key in path {
            switch cur {
            case .table(let t):
                guard let next = t[key] else { return nil }
                cur = next
            case .array(let a):
                if let i = Int(key) {
                    guard i >= 0, i < a.count else { return nil }
                    cur = a[i]
                } else {
                    // chave não-numérica sobre array = último elemento (regra array-of-tables)
                    guard let last = a.last else { return nil }
                    guard case .table(let t) = last, let next = t[key] else { return nil }
                    cur = next
                }
            default:
                return nil
            }
        }
        return cur
    }

    static func ensurePath(_ root: inout [String: TOMLValue], path: [String]) throws {
        guard !path.isEmpty else { return }
        for depth in 1...path.count {
            let sub = Array(path[0..<depth])
            if get(root, path: sub) == nil {
                try setValue(&root, path: sub, value: .table([:]))
            }
        }
    }

    static func setValue(_ root: inout [String: TOMLValue], path: [String], value: TOMLValue) throws {
        guard let first = path.first else { return }
        if path.count == 1 { root[first] = value; return }
        var container: TOMLValue
        switch root[first] {
        case .some(let v): container = v
        case nil:
            container = .table([:])
            root[first] = container
        default: throw TOMLError.parse("conflito de tipos em \(first)", line: 0)
        }
        try setIn(&container, path: Array(path.dropFirst()), value: value)
        root[first] = container
    }

    private static func setIn(_ node: inout TOMLValue, path: [String], value: TOMLValue) throws {
        guard let first = path.first else { return }
        if path.count == 1 {
            switch node {
            case .table(var t):
                t[first] = value
                node = .table(t)
            case .array(var a):
                if let i = Int(first) {
                    guard i >= 0, i < a.count else { throw TOMLError.parse("índice inválido \(first)", line: 0) }
                    a[i] = value
                } else {
                    // chave não-numérica sobre array = último elemento (array-of-tables)
                    guard var child = a.last, case .table(var t) = child else {
                        throw TOMLError.parse("último elemento não é tabela", line: 0)
                    }
                    t[first] = value
                    a[a.count - 1] = .table(t)
                }
                node = .array(a)
            default: throw TOMLError.parse("conflito de tipos em \(first)", line: 0)
            }
            return
        }
        switch node {
        case .table(var t):
            var child: TOMLValue
            switch t[first] {
            case .some(let v): child = v
            case nil:
                child = .table([:])
                t[first] = child
            default: throw TOMLError.parse("conflito de tipos em \(first)", line: 0)
            }
            try setIn(&child, path: Array(path.dropFirst()), value: value)
            t[first] = child
            node = .table(t)
        case .array(var a):
            if let i = Int(first) {
                guard i >= 0, i < a.count else { throw TOMLError.parse("índice inválido \(first)", line: 0) }
                var child = a[i]
                try setIn(&child, path: Array(path.dropFirst()), value: value)
                a[i] = child
            } else {
                // chave não-numérica sobre array = último elemento (array-of-tables)
                guard var child = a.last else { throw TOMLError.parse("array vazio", line: 0) }
                try setIn(&child, path: path, value: value)
                a[a.count - 1] = child
            }
            node = .array(a)
        default: throw TOMLError.parse("conflito de tipos", line: 0)
        }
    }

    static func appendArrayTable(_ root: inout [String: TOMLValue], path: [String]) throws {
        var arr: [TOMLValue]
        switch get(root, path: path) {
        case .array(let a): arr = a
        case nil: arr = []
        default: throw TOMLError.parse("caminho já existe e não é array de tabelas", line: 0)
        }
        arr.append(.table([:]))
        try setValue(&root, path: path, value: .array(arr))
    }

    static func arrayCount(_ root: inout [String: TOMLValue], path: [String]) -> Int {
        get(root, path: path)?.arrayValue?.count ?? 0
    }

    // MARK: - Léxico

    static func stripComment(_ line: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        for ch in line {
            if escaped { out.append(ch); escaped = false; continue }
            if ch == "\\" && inString { out.append(ch); escaped = true; continue }
            if ch == "\"" { inString.toggle(); out.append(ch); continue }
            if ch == "#" && !inString { break }
            out.append(ch)
        }
        return out
    }

    static func splitPath(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inString = false
        for ch in s {
            if ch == "\"" { inString.toggle(); continue }
            if ch == "." && !inString { parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(ch)
        }
        parts.append(cur.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }

    static func keyValueSplit(_ line: String) -> String.Index? {
        var inString = false
        var escaped = false
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if escaped { escaped = false }
            else if ch == "\\" && inString { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if ch == "=" && !inString { return idx }
            idx = line.index(after: idx)
        }
        return nil
    }

    static func parseValue(_ raw: String, line: Int) throws -> TOMLValue {
        let v = raw.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\"") {
            guard v.hasSuffix("\""), v.count >= 2 else { throw TOMLError.parse("string sem fechamento", line: line) }
            return .string(unescape(String(v.dropFirst().dropLast())))
        }
        switch v {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: break
        }
        if let i = Int(v.replacingOccurrences(of: "_", with: "")) { return .int(i) }
        if let d = Double(v.replacingOccurrences(of: "_", with: "")) { return .double(d) }
        throw TOMLError.parse("valor não suportado: \(v.prefix(30))", line: line)
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let ch = it.next() {
            if ch == "\\" {
                guard let esc = it.next() else { break }
                switch esc {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: out.append(esc)
                }
            } else { out.append(ch) }
        }
        return out
    }
}
