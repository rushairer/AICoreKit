import AICore
import Foundation

public struct AICancellationProbe:
    Sendable
{
    public let request: AIRequest
    public let delayMilliseconds:
        UInt64

    public init(
        request: AIRequest,
        delayMilliseconds: UInt64 = 50
    ) {
        self.request = request
        self.delayMilliseconds =
            delayMilliseconds
    }
}

public struct AIDeviceValidationRunner:
    Sendable
{
    public init() {}

    public func run(
        provider: any AIProvider,
        request: AIRequest,
        cancellationProbe:
            AICancellationProbe? = nil
    ) async -> AIDeviceValidationReport {
        var steps:
            [AIDiagnosticStep] = []

        let availabilityResult =
            await measureAvailability(
                provider
            )
        steps.append(
            availabilityResult.step
        )

        guard
            availabilityResult
                .availability
                == .available
        else {
            return report(
                provider: provider,
                steps: steps
            )
        }

        let resourceManager =
            provider
            as? any AIResourceManaging
        let persistentManager =
            provider
            as? any AIPersistentResourceManaging

        var preparationSucceeded = true
        var persistentPreparedBefore:
            Bool?
        var persistentPreparedAfterPrepare:
            Bool?

        if let persistentManager {
            persistentPreparedBefore =
                await persistentManager
                .isPersistentlyPrepared()
            let persistentPrepareStep =
                await measureThrowing(
                    operation:
                        .preparePersistentResources
                ) {
                    try await persistentManager
                        .preparePersistentResources()
                }

            steps.append(
                persistentPrepareStep
            )
            preparationSucceeded =
                persistentPrepareStep.status
                == .succeeded

            persistentPreparedAfterPrepare =
                await persistentManager
                .isPersistentlyPrepared()

            if preparationSucceeded {
                let loadStep =
                    await measureThrowing(
                        operation:
                            .loadPreparedResources
                    ) {
                        try await persistentManager
                            .loadPreparedResources()
                    }

                steps.append(loadStep)
                preparationSucceeded =
                    loadStep.status
                    == .succeeded
            } else {
                steps.append(
                    skippedStep(
                        operation:
                            .loadPreparedResources,
                        message:
                            "Runtime load skipped because persistent preparation failed."
                    )
                )
            }
        } else if let resourceManager {
            let prepareStep =
                await measureThrowing(
                    operation:
                        .prepareResources
                ) {
                    try await resourceManager
                        .prepareResources()
                }

            steps.append(prepareStep)
            preparationSucceeded =
                prepareStep.status
                == .succeeded
        } else {
            steps.append(
                skippedStep(
                    operation:
                        .prepareResources,
                    message:
                        "Provider does not implement AIResourceManaging."
                )
            )
        }

        if preparationSucceeded {
            let generateStep =
                await measureThrowing(
                    operation: .generate
                ) {
                    _ = try await provider
                        .generate(request)
                }

            steps.append(generateStep)

            if let cancellationProbe {
                steps.append(
                    await measureCancellation(
                        provider: provider,
                        probe:
                            cancellationProbe
                    )
                )
            }
        } else {
            steps.append(
                skippedStep(
                    operation: .generate,
                    message:
                        "Generation skipped because resource preparation failed."
                )
            )

            if cancellationProbe != nil {
                steps.append(
                    skippedStep(
                        operation:
                            .cancellationProbe,
                        message:
                            "Cancellation probe skipped because resource preparation failed."
                    )
                )
            }
        }

        if let resourceManager {
            steps.append(
                await measureThrowing(
                    operation:
                        .releaseResources
                ) {
                    try await resourceManager
                        .releaseResources()
                }
            )
        } else {
            steps.append(
                skippedStep(
                    operation:
                        .releaseResources,
                    message:
                        "Provider does not implement AIResourceManaging."
                )
            )
        }

        let persistentEvidence:
            AIPersistentPreparationEvidence?

        if
            let persistentManager,
            let preparedBeforeRun =
                persistentPreparedBefore,
            let preparedAfterPrepare =
                persistentPreparedAfterPrepare
        {
            let preparedAfterRelease =
                await persistentManager
                .isPersistentlyPrepared()

            persistentEvidence =
                AIPersistentPreparationEvidence(
                    preparedBeforeRun:
                        preparedBeforeRun,
                    preparedAfterPrepare:
                        preparedAfterPrepare,
                    preparedAfterRelease:
                        preparedAfterRelease
                )
        } else {
            persistentEvidence = nil
        }

        return report(
            provider: provider,
            steps: steps,
            persistentPreparation:
                persistentEvidence
        )
    }

    private func report(
        provider: any AIProvider,
        steps: [AIDiagnosticStep],
        persistentPreparation:
            AIPersistentPreparationEvidence? = nil
    ) -> AIDeviceValidationReport {
        AIDeviceValidationReport(
            createdAt: Date(),
            providerID: provider.id,
            providerDisplayName:
                provider.displayName,
            capabilitiesRawValue:
                provider
                .capabilities
                .rawValue,
            steps: steps,
            persistentPreparation:
                persistentPreparation
        )
    }

    private func measureAvailability(
        _ provider: any AIProvider
    ) async -> (
        availability: AIAvailability,
        step: AIDiagnosticStep
    ) {
        let before =
            AIProcessMetrics.snapshot()
        let started =
            DispatchTime.now()
                .uptimeNanoseconds

        let availability =
            await provider.availability()

        let finished =
            DispatchTime.now()
                .uptimeNanoseconds
        let after =
            AIProcessMetrics.snapshot()

        let status:
            AIDiagnosticStatus
        let message: String?

        switch availability {
        case .available:
            status = .succeeded
            message = nil
        case .unavailable(
            let reason
        ):
            status = .unavailable
            message =
                String(
                    describing: reason
                )
        }

        return (
            availability,
            AIDiagnosticStep(
                operation:
                    .availability,
                status: status,
                durationMilliseconds:
                    milliseconds(
                        from: started,
                        to: finished
                    ),
                message: message,
                before: before,
                after: after
            )
        )
    }

    private func measureThrowing(
        operation:
            AIDiagnosticOperation,
        body:
            @escaping @Sendable
            () async throws -> Void
    ) async -> AIDiagnosticStep {
        let before =
            AIProcessMetrics.snapshot()
        let started =
            DispatchTime.now()
                .uptimeNanoseconds

        let status:
            AIDiagnosticStatus
        let message: String?

        do {
            try await body()
            status = .succeeded
            message = nil
        } catch is CancellationError {
            status = .cancelled
            message = "CancellationError"
        } catch let error as AIError {
            if error == .cancelled {
                status = .cancelled
            } else {
                status = .failed
            }
            message =
                String(
                    describing: error
                )
        } catch {
            status = .failed
            message =
                error.localizedDescription
        }

        let finished =
            DispatchTime.now()
                .uptimeNanoseconds
        let after =
            AIProcessMetrics.snapshot()

        return AIDiagnosticStep(
            operation: operation,
            status: status,
            durationMilliseconds:
                milliseconds(
                    from: started,
                    to: finished
                ),
            message: message,
            before: before,
            after: after
        )
    }

    private func measureCancellation(
        provider: any AIProvider,
        probe: AICancellationProbe
    ) async -> AIDiagnosticStep {
        await measureThrowing(
            operation:
                .cancellationProbe
        ) {
            let task = Task {
                try await provider
                    .generate(
                        probe.request
                    )
            }

            if probe.delayMilliseconds > 0 {
                try await Task.sleep(
                    nanoseconds:
                        probe
                        .delayMilliseconds
                        * 1_000_000
                )
            }

            task.cancel()

            do {
                _ = try await task.value
                throw CancellationProbeError
                    .completedBeforeCancellation
            } catch is CancellationError {
                throw AIError.cancelled
            } catch let error as AIError {
                if error == .cancelled {
                    throw error
                }
                throw error
            }
        }
    }

    private func skippedStep(
        operation:
            AIDiagnosticOperation,
        message: String
    ) -> AIDiagnosticStep {
        let snapshot =
            AIProcessMetrics.snapshot()

        return AIDiagnosticStep(
            operation: operation,
            status: .skipped,
            durationMilliseconds: 0,
            message: message,
            before: snapshot,
            after: snapshot
        )
    }

    private func milliseconds(
        from start: UInt64,
        to end: UInt64
    ) -> Double {
        Double(
            end >= start
            ? end - start
            : 0
        ) / 1_000_000
    }
}

private enum CancellationProbeError:
    LocalizedError
{
    case completedBeforeCancellation

    var errorDescription: String? {
        switch self {
        case .completedBeforeCancellation:
            return
                "Generation completed before cancellation could be observed."
        }
    }
}
