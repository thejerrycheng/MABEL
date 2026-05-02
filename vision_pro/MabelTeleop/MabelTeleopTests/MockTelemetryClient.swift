//
//  MockTelemetryClient.swift
//  MabelTeleopTests
//

import Foundation
@testable import MabelTeleop

final class MockTelemetryClient: TelemetryClient, @unchecked Sendable {

    private let lock = NSLock()
    private var _status: ConnectionStatus = .disconnected
    private(set) var sentFrames: [TeleopFrame] = []
    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0

    private var statusContinuations: [AsyncStream<ConnectionStatus>.Continuation] = []
    private var stateContinuations:  [AsyncStream<RobotState>.Continuation]      = []

    var status: ConnectionStatus {
        get async {
            lock.lock(); defer { lock.unlock() }
            return _status
        }
    }

    func statusStream() -> AsyncStream<ConnectionStatus> {
        AsyncStream { continuation in
            lock.lock()
            statusContinuations.append(continuation)
            continuation.yield(_status)
            lock.unlock()
        }
    }

    func robotStateStream() -> AsyncStream<RobotState> {
        AsyncStream { continuation in
            lock.lock()
            stateContinuations.append(continuation)
            lock.unlock()
        }
    }

    func connect() async {
        lock.lock()
        connectCalls += 1
        _status = .connected
        let conts = statusContinuations
        lock.unlock()
        conts.forEach { $0.yield(.connected) }
    }

    func disconnect() async {
        lock.lock()
        disconnectCalls += 1
        _status = .disconnected
        let conts = statusContinuations
        lock.unlock()
        conts.forEach { $0.yield(.disconnected) }
    }

    func send(_ frame: TeleopFrame) async {
        lock.lock()
        sentFrames.append(frame)
        lock.unlock()
    }

    // Test helpers

    func simulateRobotState(_ state: RobotState) {
        lock.lock()
        let conts = stateContinuations
        lock.unlock()
        conts.forEach { $0.yield(state) }
    }
}
