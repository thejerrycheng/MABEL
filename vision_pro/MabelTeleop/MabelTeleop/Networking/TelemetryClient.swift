//
//  TelemetryClient.swift
//  MabelTeleop
//

import Foundation

/// Abstract telemetry transport. Swap in a mock for unit tests or a
/// different implementation (e.g. gRPC) without touching view models.
public protocol TelemetryClient: AnyObject, Sendable {
    /// Current connection status. Observable via `statusStream`.
    var status: ConnectionStatus { get async }

    /// Pushes a status update each time the transport changes state.
    func statusStream() -> AsyncStream<ConnectionStatus>

    /// Inbound robot state messages.
    func robotStateStream() -> AsyncStream<RobotState>

    /// Begin connecting. Idempotent.
    func connect() async

    /// Close the connection.
    func disconnect() async

    /// Send a pose frame. Drops silently if not connected — pose data is
    /// ephemeral and we'd rather skip than buffer stale frames.
    func send(_ frame: TeleopFrame) async
}
