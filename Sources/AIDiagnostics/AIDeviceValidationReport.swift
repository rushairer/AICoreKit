import AICore
import Foundation

public enum AIDiagnosticOperation:
    String,
    Hashable,
    Sendable,
    Codable
{
    case availability
    case prepareResources
    case generate
    case cancellationProbe
    case releaseResources
}

public enum AIDiagnosticStatus:
    String,
    Hashable,
    Sendable,
    Codable
{
    case succeeded
    case unavailable
    case cancelled
    case failed
    case skipped
}

public struct AIDiagnosticStep:
    Hashable,
    Sendable,
    Codable
{
    public let operation:
        AIDiagnosticOperation
    public let status:
        AIDiagnosticStatus
    public let durationMilliseconds:
        Double
    public let message:
        String?
    public let before:
        AIProcessSnapshot
    public let after:
        AIProcessSnapshot

    public init(
        operation: AIDiagnosticOperation,
        status: AIDiagnosticStatus,
        durationMilliseconds: Double,
        message: String?,
        before: AIProcessSnapshot,
        after: AIProcessSnapshot
    ) {
        self.operation = operation
        self.status = status
        self.durationMilliseconds =
            durationMilliseconds
        self.message = message
        self.before = before
        self.after = after
    }
}

public struct AIDeviceValidationReport:
    Hashable,
    Sendable,
    Codable
{
    public let createdAt: Date
    public let providerID:
        AIProviderID
    public let providerDisplayName:
        String
    public let capabilitiesRawValue:
        UInt64
    public let steps:
        [AIDiagnosticStep]

    public init(
        createdAt: Date,
        providerID: AIProviderID,
        providerDisplayName: String,
        capabilitiesRawValue: UInt64,
        steps: [AIDiagnosticStep]
    ) {
        self.createdAt = createdAt
        self.providerID = providerID
        self.providerDisplayName =
            providerDisplayName
        self.capabilitiesRawValue =
            capabilitiesRawValue
        self.steps = steps
    }

    public func jsonData(
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy =
            .iso8601

        if prettyPrinted {
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]
        }

        return try encoder.encode(self)
    }

    public func jsonString(
        prettyPrinted: Bool = true
    ) throws -> String {
        let data =
            try jsonData(
                prettyPrinted:
                    prettyPrinted
            )

        guard
            let value = String(
                data: data,
                encoding: .utf8
            )
        else {
            throw AIError
                .decodingFailure(
                    "Diagnostic report was not UTF-8"
                )
        }

        return value
    }
}
