import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum AIThermalState:
    String,
    Hashable,
    Sendable,
    Codable
{
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public struct AIProcessSnapshot:
    Hashable,
    Sendable,
    Codable
{
    public let timestamp: Date
    public let physicalFootprintBytes: UInt64?
    public let residentMemoryBytes: UInt64?
    public let thermalState: AIThermalState
    public let lowPowerModeEnabled: Bool
    public let operatingSystemVersion: String

    public init(
        timestamp: Date,
        physicalFootprintBytes: UInt64?,
        residentMemoryBytes: UInt64?,
        thermalState: AIThermalState,
        lowPowerModeEnabled: Bool,
        operatingSystemVersion: String
    ) {
        self.timestamp = timestamp
        self.physicalFootprintBytes =
            physicalFootprintBytes
        self.residentMemoryBytes =
            residentMemoryBytes
        self.thermalState = thermalState
        self.lowPowerModeEnabled =
            lowPowerModeEnabled
        self.operatingSystemVersion =
            operatingSystemVersion
    }
}

public enum AIProcessMetrics {
    public static func snapshot(
        at date: Date = Date()
    ) -> AIProcessSnapshot {
        let processInfo =
            ProcessInfo.processInfo
        let memory =
            currentMemory()

        return AIProcessSnapshot(
            timestamp: date,
            physicalFootprintBytes:
                memory.physicalFootprint,
            residentMemoryBytes:
                memory.resident,
            thermalState:
                thermalState(
                    processInfo
                        .thermalState
                ),
            lowPowerModeEnabled:
                processInfo
                .isLowPowerModeEnabled,
            operatingSystemVersion:
                processInfo
                .operatingSystemVersionString
        )
    }

    private static func thermalState(
        _ state:
            ProcessInfo.ThermalState
    ) -> AIThermalState {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .unknown
        }
    }

    private static func currentMemory()
        -> (
            physicalFootprint: UInt64?,
            resident: UInt64?
        )
    {
        #if canImport(Darwin)
        var info =
            task_vm_info_data_t()
        var count =
            mach_msg_type_number_t(
                MemoryLayout<
                    task_vm_info_data_t
                >.size
                / MemoryLayout<
                    natural_t
                >.size
            )

        let result =
            withUnsafeMutablePointer(
                to: &info
            ) {
                pointer in

                pointer
                    .withMemoryRebound(
                        to:
                            integer_t.self,
                        capacity:
                            Int(count)
                    ) {
                        rebound in

                        task_info(
                            mach_task_self_,
                            task_flavor_t(
                                TASK_VM_INFO
                            ),
                            rebound,
                            &count
                        )
                    }
            }

        guard result == KERN_SUCCESS else {
            return (nil, nil)
        }

        return (
            UInt64(
                info.phys_footprint
            ),
            UInt64(
                info.resident_size
            )
        )
        #else
        return (nil, nil)
        #endif
    }
}


public enum AIDiagnosticEnvironmentProbe {
    public static func current()
        -> AIDiagnosticEnvironment
    {
        AIDiagnosticEnvironment(
            hardwareModelIdentifier:
                hardwareModelIdentifier(),
            architecture:
                architectureIdentifier(),
            operatingSystemVersion:
                ProcessInfo.processInfo
                .operatingSystemVersionString
        )
    }

    private static func hardwareModelIdentifier()
        -> String?
    {
        #if canImport(Darwin)
        var size: size_t = 0
        guard
            sysctlbyname(
                "hw.machine",
                nil,
                &size,
                nil,
                0
            ) == 0,
            size > 0
        else {
            return nil
        }

        var value =
            [CChar](
                repeating: 0,
                count: Int(size)
            )

        guard
            sysctlbyname(
                "hw.machine",
                &value,
                &size,
                nil,
                0
            ) == 0
        else {
            return nil
        }

        return String(
            cString: value
        )
        #else
        return nil
        #endif
    }

    private static func architectureIdentifier()
        -> String
    {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(i386)
        return "i386"
        #elseif arch(arm)
        return "arm"
        #else
        return "unknown"
        #endif
    }
}
