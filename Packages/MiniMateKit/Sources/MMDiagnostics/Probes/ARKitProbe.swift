import Foundation
#if os(iOS)
import ARKit
#endif

/// Whether ARKit face tracking is supported on this device.
public struct ARKitProbe: CapabilityProbe {
    public let id = CapabilityID.arFaceTracking

    public init() {}

    public func run() async throws -> CapabilityResult {
        #if os(iOS)
        let status: CapabilityStatus = ARFaceTrackingConfiguration.isSupported
            ? .available
            : .unavailable(reason: "设备不支持人脸追踪")
        return CapabilityResult(id: id, status: status, detail: nil, duration: .zero)
        #else
        return CapabilityResult(
            id: id,
            status: .unavailable(reason: "ARKit 仅在 iOS 可用"),
            detail: nil,
            duration: .zero
        )
        #endif
    }
}
