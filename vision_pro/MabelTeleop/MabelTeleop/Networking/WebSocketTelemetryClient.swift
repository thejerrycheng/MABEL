//
//  WebSocketTelemetryClient.swift
//  MabelTeleop
//
//  Production implementation of `TelemetryClient` over URLSessionWebSocketTask.
//  Responsibilities:
//    - Maintain an auto-reconnecting socket to the robot's telemetry server.
//    - Encode outbound TeleopFrames with a shared WireCodec.
//    - Decode inbound envelopes and fan out to consumer streams.
//
//  Threading: all mutable state lives inside an actor, so callers can hit
//  `send(_:)` from anywhere without worrying about data races.
//

import Foundation
import OSLog
import QuartzCore

public actor WebSocketTelemetryClient: TelemetryClient {

    // MARK: - Dependencies

    private let url: URL
    private let session: URLSession
    private let log = Logger(subsystem: "com.mabel.teleop", category: "ws")
    private let reconnectDelay: TimeInterval

    // MARK: - State

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var shouldReconnect = false
    private let heartbeatInterval: TimeInterval
    private let heartbeatTimeout: TimeInterval
    private var lastInboundAt: TimeInterval = 0

    private var _status: ConnectionStatus = .disconnected
    public var status: ConnectionStatus { _status }

    private var statusContinuations: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]
    private var stateContinuations:  [UUID: AsyncStream<RobotState>.Continuation]      = [:]

    // MARK: - Init

    public init(
        url: URL,
        session: URLSession = .shared,
        reconnectDelay: TimeInterval = 1.5,
        heartbeatInterval: TimeInterval = 2.0,
        heartbeatTimeout: TimeInterval = 6.0
    ) {
        self.url = url
        self.session = session
        self.reconnectDelay = reconnectDelay
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
    }

    // MARK: - Streams

    public nonisolated func statusStream() -> AsyncStream<ConnectionStatus> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addStatus(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeStatus(id: id) }
            }
        }
    }

    public nonisolated func robotStateStream() -> AsyncStream<RobotState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addState(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeState(id: id) }
            }
        }
    }

    private func addStatus(id: UUID, continuation: AsyncStream<ConnectionStatus>.Continuation) {
        statusContinuations[id] = continuation
        continuation.yield(_status)
    }
    private func removeStatus(id: UUID) { statusContinuations.removeValue(forKey: id) }
    private func addState(id: UUID, continuation: AsyncStream<RobotState>.Continuation) {
        stateContinuations[id] = continuation
    }
    private func removeState(id: UUID) { stateContinuations.removeValue(forKey: id) }

    // MARK: - Lifecycle

    public func connect() async {
        guard task == nil else { return }
        shouldReconnect = true
        await openSocket()
    }

    public func disconnect() async {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        updateStatus(.disconnected)
    }

    // MARK: - Sending

    public func send(_ frame: TeleopFrame) async {
        guard let task, _status.isConnected else { return }
        do {
            let data = try WireCodec.encode(frame, as: .teleopFrame)
            try await task.send(.data(data))
        } catch {
            log.error("send failed: \(error.localizedDescription, privacy: .public)")
            await handleDisconnect(reason: error.localizedDescription)
        }
    }

    // MARK: - Internals

    private func openSocket() async {
        updateStatus(.connecting)
        let newTask = session.webSocketTask(with: url)
        self.task = newTask
        newTask.resume()

        // Send a hello so the server can identify us.
        let hello: [String: String] = ["client": "VisionPro-MabelTeleop", "version": "1.0"]
        if let helloData = try? WireCodec.encode(hello, as: .hello) {
            try? await newTask.send(.data(helloData))
        }

        updateStatus(.connected)
        lastInboundAt = CACurrentMediaTime()
        receiveLoop = Task { await runReceiveLoop(on: newTask) }
        heartbeatTask = Task { await runHeartbeatLoop(on: newTask) }
    }

    /// Sends pings on a fixed cadence and tears the socket down if no
    /// inbound traffic has arrived within `heartbeatTimeout`. This is
    /// what surfaces a silently-dead TCP connection quickly.
    private func runHeartbeatLoop(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let sleepNs = UInt64(heartbeatInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNs)
            if Task.isCancelled { return }
            guard self.task === task else { return }   // socket was replaced

            // Send ping.
            let payload = ["t": CACurrentMediaTime()]
            if let data = try? WireCodec.encode(payload, as: .ping) {
                do {
                    try await task.send(.data(data))
                } catch {
                    await handleDisconnect(reason: "heartbeat send failed")
                    return
                }
            }

            // Check freshness.
            if CACurrentMediaTime() - lastInboundAt > heartbeatTimeout {
                log.error("heartbeat timeout — no inbound in \(self.heartbeatTimeout)s")
                await handleDisconnect(reason: "heartbeat timeout")
                return
            }
        }
    }

    private func runReceiveLoop(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    handleIncoming(data)
                case .string(let s):
                    if let data = s.data(using: .utf8) { handleIncoming(data) }
                @unknown default:
                    continue
                }
            } catch {
                await handleDisconnect(reason: error.localizedDescription)
                return
            }
        }
    }

    private func handleIncoming(_ data: Data) {
        lastInboundAt = CACurrentMediaTime()
        do {
            let envelope = try WireCodec.decodeEnvelope(data)
            switch envelope.type {
            case .robotState:
                let state = try WireCodec.decodePayload(RobotState.self, from: envelope)
                for (_, c) in stateContinuations { c.yield(state) }
            case .ping:
                Task { await self.sendPong() }
            case .pong, .hello, .error, .teleopFrame:
                break
            }
        } catch {
            log.error("decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendPong() async {
        guard let task else { return }
        let payload = ["t": Date().timeIntervalSince1970]
        if let data = try? WireCodec.encode(payload, as: .pong) {
            try? await task.send(.data(data))
        }
    }

    private func handleDisconnect(reason: String) async {
        task = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        updateStatus(.failed(reason: reason))

        guard shouldReconnect else { return }
        let delay = reconnectDelay
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, await self.shouldReconnect else { return }
            await self.openSocket()
        }
    }

    private func updateStatus(_ new: ConnectionStatus) {
        _status = new
        for (_, c) in statusContinuations { c.yield(new) }
    }
}
