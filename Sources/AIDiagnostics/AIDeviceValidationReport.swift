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
    case preparePersistentResources
    case loadPreparedResources
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

public struct AIPersistentPreparationEvidence:
    Hashable,
    Sendable,
    Codable
{
    public let preparedBeforeRun: Bool
    public let preparedAfterPrepare: Bool
    public let preparedAfterRelease: Bool
    public let coldPreparationPerformed: Bool

    public init(
        preparedBeforeRun: Bool,
        preparedAfterPrepare: Bool,
        preparedAfterRelease: Bool
    ) {
        self.preparedBeforeRun =
            preparedBeforeRun
        self.preparedAfterPrepare =
            preparedAfterPrepare
        self.preparedAfterRelease =
            preparedAfterRelease
        self.coldPreparationPerformed =
            !preparedBeforeRun
            && preparedAfterPrepare
    }
}

public struct AIDiagnosticEnvironment:
    Hashable,
    Sendable,
    Codable
{
    public let hardwareModelIdentifier: String?
    public let architecture: String
    public let operatingSystemVersion: String

    public init(
        hardwareModelIdentifier: String?,
        architecture: String,
        operatingSystemVersion: String
    ) {
        self.hardwareModelIdentifier =
            hardwareModelIdentifier
        self.architecture = architecture
        self.operatingSystemVersion =
            operatingSystemVersion
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
    public let persistentPreparation:
        AIPersistentPreparationEvidence?
    public let environment:
        AIDiagnosticEnvironment
    public let metadata:
        [String: String]

    public init(
        createdAt: Date,
        providerID: AIProviderID,
        providerDisplayName: String,
        capabilitiesRawValue: UInt64,
        steps: [AIDiagnosticStep],
        persistentPreparation:
            AIPersistentPreparationEvidence? = nil,
        environment:
            AIDiagnosticEnvironment =
                AIDiagnosticEnvironment(
                    hardwareModelIdentifier: nil,
                    architecture: "unknown",
                    operatingSystemVersion:
                        ProcessInfo.processInfo
                        .operatingSystemVersionString
                ),
        metadata: [String: String] = [:]
    ) {
        self.createdAt = createdAt
        self.providerID = providerID
        self.providerDisplayName =
            providerDisplayName
        self.capabilitiesRawValue =
            capabilitiesRawValue
        self.steps = steps
        self.persistentPreparation =
            persistentPreparation
        self.environment = environment
        self.metadata = metadata
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
