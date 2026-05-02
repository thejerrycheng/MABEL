//
//  WireCodecTests.swift
//  MabelTeleopTests
//

import XCTest
@testable import MabelTeleop
import simd

final class WireCodecTests: XCTestCase {

    func test_teleopFrame_roundTrip_preservesAllFields() throws {
        let frame = Self.makeFrame()

        let encoded = try WireCodec.encode(frame, as: .teleopFrame)
        let envelope = try WireCodec.decodeEnvelope(encoded)

        XCTAssertEqual(envelope.type, .teleopFrame)

        let decoded = try WireCodec.decodePayload(TeleopFrame.self, from: envelope)
        XCTAssertEqual(decoded, frame)
    }

    func test_robotState_roundTrip_preservesAllFields() throws {
        let state = RobotState(
            timestamp: 123.456,
            mode: .teleop,
            battery: .init(percentage: 0.42, voltage: 23.7, charging: false),
            jointPositions: ["arm_l_shoulder": 1.1, "arm_r_shoulder": -1.1],
            diagnostics: [
                .init(level: .warning, component: "arm_l", message: "High current")
            ],
            latencyMs: 42.0
        )

        let encoded = try WireCodec.encode(state, as: .robotState)
        let envelope = try WireCodec.decodeEnvelope(encoded)
        let decoded = try WireCodec.decodePayload(RobotState.self, from: envelope)

        XCTAssertEqual(decoded, state)
    }

    func test_transform4x4_roundTrip_preservesMatrix() {
        let m = simd_float4x4(
            SIMD4<Float>(1, 2, 3, 4),
            SIMD4<Float>(5, 6, 7, 8),
            SIMD4<Float>(9, 10, 11, 12),
            SIMD4<Float>(13, 14, 15, 16)
        )
        let t = Transform4x4(m)
        XCTAssertEqual(t.simd, m)
    }

    // MARK: - Factory

    private static func makeFrame() -> TeleopFrame {
        let identity = Transform4x4(matrix_identity_float4x4)
        let joints = HandJoint.allCases.map {
            HandJointPose(joint: $0, localTransform: identity, isTracked: true)
        }
        return TeleopFrame(
            sequence: 42,
            timestamp: 9.9,
            head: HeadPose(transform: identity, trackingState: .normal),
            leftHand:  HandPose(chirality: .left,  anchorTransform: identity, joints: joints, isTracked: true),
            rightHand: HandPose(chirality: .right, anchorTransform: identity, joints: joints, isTracked: true)
        )
    }
}
