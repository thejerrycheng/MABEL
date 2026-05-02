//
//  RobotState.swift
//  MabelTeleop
//
//  Describes the state the robot publishes back to the headset:
//  joint positions, battery, mode, and any operator-facing status.
//

import Foundation

public struct RobotState: Codable, Equatable, Sendable {
    public var timestamp: TimeInterval
    public var mode: Mode
    public var battery: Battery?
    public var jointPositions: [String: Float]
    public var diagnostics: [Diagnostic]
    public var latencyMs: Double?

    public enum Mode: String, Codable, Sendable {
        case idle, teleop, autonomous, estopped, recovering
    }

    public struct Battery: Codable, Equatable, Sendable {
        public var percentage: Double   // 0...1
        public var voltage: Double
        public var charging: Bool
    }

    public struct Diagnostic: Codable, Equatable, Sendable, Identifiable {
        public var id: String { "\(component):\(message)" }
        public var level: Level
        public var component: String
        public var message: String

        public enum Level: String, Codable, Sendable {
            case info, warning, error
        }
    }

    public static let disconnected = RobotState(
        timestamp: 0,
        mode: .idle,
        battery: nil,
        jointPositions: [:],
        diagnostics: [],
        latencyMs: nil
    )
}
