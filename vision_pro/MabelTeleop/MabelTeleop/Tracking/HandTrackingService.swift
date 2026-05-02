//
//  HandTrackingService.swift
//  MabelTeleop
//
//  Thin, testable wrapper over ARKit's HandTrackingProvider. The service
//  owns the ARKit session lifecycle and exposes an AsyncStream of
//  (leftHand, rightHand) snapshots sampled at the provider's native rate.
//
//  Consumers should NOT touch ARKit directly — that keeps the rest of
//  the app unit-testable on the simulator/CI.
//

import Foundation
import ARKit
import QuartzCore
import simd

@MainActor
public final class HandTrackingService {

    public struct Snapshot: Sendable {
        public var left: HandPose?
        public var right: HandPose?
        public var timestamp: TimeInterval
    }

    private let session: ARKitSession
    private let provider: HandTrackingProvider
    private var isRunning = false

    public init(session: ARKitSession = ARKitSession()) {
        self.session = session
        self.provider = HandTrackingProvider()
    }

    // MARK: - Authorization

    public static var isSupported: Bool {
        HandTrackingProvider.isSupported
    }

    public func requestAuthorization() async -> Bool {
        let result = await session.requestAuthorization(for: [.handTracking])
        return result[.handTracking] == .allowed
    }

    // MARK: - Lifecycle

    public func start() async throws {
        guard !isRunning else { return }
        try await session.run([provider])
        isRunning = true
    }

    public func stop() {
        session.stop()
        isRunning = false
    }

    // MARK: - Streaming

    /// Yields a snapshot every time ARKit publishes a hand anchor update.
    public func snapshots() -> AsyncStream<Snapshot> {
        AsyncStream { continuation in
            let task = Task { [provider] in
                var left: HandPose?
                var right: HandPose?
                for await update in provider.anchorUpdates {
                    let anchor = update.anchor
                    let pose = Self.makePose(from: anchor)
                    switch anchor.chirality {
                    case .left:  left = pose
                    case .right: right = pose
                    @unknown default: continue
                    }
                    continuation.yield(Snapshot(
                        left: left, right: right,
                        timestamp: CACurrentMediaTimeSafe()
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Conversion

    private static func makePose(from anchor: HandAnchor) -> HandPose {
        let chirality: Chirality = (anchor.chirality == .left) ? .left : .right
        var joints: [HandJointPose] = []

        if anchor.isTracked, let skeleton = anchor.handSkeleton {
            joints.reserveCapacity(HandJoint.allCases.count)
            for joint in HandJoint.allCases {
                guard let arkitName = joint.arkitName else { continue }
                let j = skeleton.joint(arkitName)
                joints.append(HandJointPose(
                    joint: joint,
                    localTransform: Transform4x4(j.anchorFromJointTransform),
                    isTracked: j.isTracked
                ))
            }
        }

        return HandPose(
            chirality: chirality,
            anchorTransform: Transform4x4(anchor.originFromAnchorTransform),
            joints: joints,
            isTracked: anchor.isTracked
        )
    }
}

// MARK: - Joint name bridging

private extension HandJoint {
    /// Maps our serializable enum to ARKit's `HandSkeleton.JointName`.
    /// Any joints not exposed by the current SDK return nil and are skipped.
    var arkitName: HandSkeleton.JointName? {
        switch self {
        case .wrist:                            return .wrist
        case .thumbKnuckle:                     return .thumbKnuckle
        case .thumbIntermediateBase:            return .thumbIntermediateBase
        case .thumbIntermediateTip:             return .thumbIntermediateTip
        case .thumbTip:                         return .thumbTip
        case .indexFingerMetacarpal:            return .indexFingerMetacarpal
        case .indexFingerKnuckle:               return .indexFingerKnuckle
        case .indexFingerIntermediateBase:      return .indexFingerIntermediateBase
        case .indexFingerIntermediateTip:       return .indexFingerIntermediateTip
        case .indexFingerTip:                   return .indexFingerTip
        case .middleFingerMetacarpal:           return .middleFingerMetacarpal
        case .middleFingerKnuckle:              return .middleFingerKnuckle
        case .middleFingerIntermediateBase:     return .middleFingerIntermediateBase
        case .middleFingerIntermediateTip:      return .middleFingerIntermediateTip
        case .middleFingerTip:                  return .middleFingerTip
        case .ringFingerMetacarpal:             return .ringFingerMetacarpal
        case .ringFingerKnuckle:                return .ringFingerKnuckle
        case .ringFingerIntermediateBase:       return .ringFingerIntermediateBase
        case .ringFingerIntermediateTip:        return .ringFingerIntermediateTip
        case .ringFingerTip:                    return .ringFingerTip
        case .littleFingerMetacarpal:           return .littleFingerMetacarpal
        case .littleFingerKnuckle:              return .littleFingerKnuckle
        case .littleFingerIntermediateBase:     return .littleFingerIntermediateBase
        case .littleFingerIntermediateTip:      return .littleFingerIntermediateTip
        case .littleFingerTip:                  return .littleFingerTip
        case .forearmWrist:                     return .forearmWrist
        case .forearmArm:                       return .forearmArm
        }
    }
}

@inline(__always)
private func CACurrentMediaTimeSafe() -> TimeInterval {
    // Isolated into a helper so tests can stub without importing QuartzCore.
    CACurrentMediaTime()
}
