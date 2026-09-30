import Foundation

public enum AIJSONValue: Hashable, Sendable, Codable {
    case object([String: AIJSONValue])
    case array([AIJSONValue])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(
            [String: AIJSONValue].self
        ) {
            self = .object(value)
        } else if let value = try? container.decode(
            [AIJSONValue].self
        ) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public init(jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw AIError.invalidRequest(
                "JSON schema must be valid UTF-8"
            )
        }

        do {
            self = try JSONDecoder().decode(
                AIJSONValue.self,
                from: data
            )
        } catch {
            throw AIError.invalidRequest(
                "Invalid JSON schema: \(error.localizedDescription)"
            )
        }
    }
}

public struct AIStructuredOutputSchema:
    Hashable,
    Sendable,
    Codable
{
    public let name: String
    public let description: String?
    public let schema: AIJSONValue
    public let strict: Bool

    public init(
        name: String,
        description: String? = nil,
        schema: AIJSONValue,
        strict: Bool = true
    ) {
        self.name = name
        self.description = description
        self.schema = schema
        self.strict = strict
    }

    public init(
        name: String,
        description: String? = nil,
        schemaJSON: String,
        strict: Bool = true
    ) throws {
        let parsed = try AIJSONValue(
            jsonString: schemaJSON
        )

        guard case .object = parsed else {
            throw AIError.invalidRequest(
                "Structured output schema must be a JSON object"
            )
        }

        self.init(
            name: name,
            description: description,
            schema: parsed,
            strict: strict
        )
    }
}
