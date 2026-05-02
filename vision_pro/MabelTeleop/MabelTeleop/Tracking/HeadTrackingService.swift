//
//  HeadTrackingService.swift
//  MabelTeleop
//
//  Polls WorldTrackingProvider for the device pose. visionOS doesn't
//  push head-pose updates as a stream (unlike hands), so the consumer
//  samples whenever it's ready to transmit a frame.
//

import Foundation
import ARKit
import QuartzCore
import simd

@MainActor
public final class HeadTrackingService {

    private let session: ARKitSession
    private let provider: WorldTrackingProvider
    private var isRunning = false

    public init(session: ARKitSession = ARKitSession()) {
        self.session = session
        self.provider = WorldTrackingProvider()
    }

    public static var isSupported: Bool {
        WorldTrackingProvider.isSupported
    }

    public func requestAuthorization() async -> Bool {
        let result = await session.requestAuthorization(for: [.worldSensing])
        return result[.worldSensing] == .allowed
    }

    public func start() async throws {
        guard !isRunning else { return }
        try await session.run([provider])
        isRunning = true
    }

    public func stop() {
        session.stop()
        isRunning = false
    }

    /// Samples the current head pose. Returns `nil` if tracking is not yet
    /// ready or the provider has no anchor available.
    public func currentPose(at timestamp: TimeInterval = CACurrentMediaTime()) -> HeadPose? {
        guard let anchor = provider.queryDeviceAnchor(atTimestamp: timestamp) else {
            return nil
        }
        return HeadPose(
            transform: Transform4x4(anchor.originFromAnchorTransform),
            trackingState: anchor.isTracked ? .normal : .limited
        )
    }
}
