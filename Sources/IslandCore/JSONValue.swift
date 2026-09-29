import Foundation

public indirect enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSONValue { object[key] ?? .null }
    public var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }

    public static func decode(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: data) }
    public func data() throws -> Data { try JSONEncoder().encode(self) }
}

public enum ProtocolFailure: Error, LocalizedError {
    case oversizedFrame, malformedFrame, incompatibleVersion, missingSnapshot, invalidPatch
    public var errorDescription: String? {
        switch self {
        case .oversizedFrame: return "Codex poslal příliš velký rámec."
        case .malformedFrame: return "Codex poslal neplatnou zprávu."
        case .incompatibleVersion: return "Změnil se protokol Codexu. Je potřeba aktualizovat Codex Island."
        case .missingSnapshot: return "Obnovuji stav chatu."
        case .invalidPatch: return "Změnu stavu nelze přečíst. Obnovuji napojení."
        }
    }
}

/// Desktop IPC uses a four-byte little-endian byte length, followed by UTF-8 JSON.
public struct FrameDecoder {
    public static let maximumBytes = 32 * 1024 * 1024
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) throws -> [JSONValue] {
        buffer.append(data)
        var frames: [JSONValue] = []
        var offset = 0
        while buffer.count - offset >= 4 {
            let length = (0..<4).reduce(0) { $0 | (Int(buffer[buffer.startIndex + offset + $1]) << ($1 * 8)) }
            guard length > 0, length <= Self.maximumBytes else { throw ProtocolFailure.oversizedFrame }
            guard buffer.count - offset >= 4 + length else { break }
            let payload = buffer.subdata(in: (offset + 4)..<(offset + 4 + length))
            do { frames.append(try JSONValue.decode(payload)) }
            catch { throw ProtocolFailure.malformedFrame }
            offset += 4 + length
        }
        if offset > 0 { buffer.removeSubrange(0..<offset) }
        return frames
    }

    public static func encode(_ value: JSONValue) throws -> Data {
        let payload = try value.data()
        guard payload.count <= maximumBytes else { throw ProtocolFailure.oversizedFrame }
        var size = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(payload)
        return frame
    }
}
