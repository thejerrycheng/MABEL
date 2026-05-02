//
//  TeleopSession.swift
//  MabelTeleop
//
//  The single source of truth the UI layer binds to. A TeleopSession
//  wires together:
//    - PoseStreamCoordinator  (ARKit)
//    - TelemetryClient        (WebSocket)
//    - VideoStreamManager     (MJPEG cameras)
//
//  Views and view models should only touch this object and its
//  @Published state — not the lower layers directly.
//

import Foundation
import Combine
import OSLog

@MainActor
public final class TeleopSession: ObservableObject {

    // MARK: - Published state

    @Published public var currentMode: TeleopMode = .manipulation
    
    @Published public private(set) var connection: ConnectionStatus = .disconnected
    @Published public private(set) var robotState: RobotState = .disconnected
    @Published public private(set) var isStreamingPoses = false
    @Published public private(set) var lastFrameSequence: UInt64 = 0
    @Published public private(set) var lastFrame: TeleopFrame?
    @Published public private(set) var lastError: String?

    // MARK: - Exposed collaborators

    public let videoManager: VideoStreamManager

    // MARK: - Dependencies

    private let configuration: AppConfiguration
    private let telemetry: TelemetryClient
    private let poseCoordinator: PoseStreamCoordinator
    private let log = Logger(subsystem: "com.mabel.teleop", category: "session")

    // MARK: - Lifecycle

    private var poseTask: Task<Void, Never>?
    private var observerTasks: [Task<Void, Never>] = []

    public init(
        configuration: AppConfiguration = .default,
        telemetry: TelemetryClient? = nil,
        handService: HandTrackingService? = nil,
        headService: HeadTrackingService? = nil,
        videoManager: VideoStreamManager? = nil
    ) {
        self.configuration = configuration

        self.telemetry = telemetry ?? WebSocketTelemetryClient(
            url: configuration.network.telemetryURL,
            reconnectDelay: configuration.video.reconnectDelay
        )

        let hand = handService ?? HandTrackingService()
        let head = headService ?? HeadTrackingService()
        self.poseCoordinator = PoseStreamCoordinator(
            handService: hand,
            headService: head,
            config: configuration.tracking
        )

        self.videoManager = videoManager ?? VideoStreamManager(configuration: configuration)

        wireObservers()
    }

    // MARK: - Public API

    /// Starts everything: auth, ARKit, WS, cameras. Safe to call multiple times.
    public func start() async {
        guard !isStreamingPoses else { return }

        guard await requestAuthorizations() else {
            lastError = "Tracking authorization was denied."
            return
        }

        do {
            try await poseCoordinator.start()
        } catch {
            lastError = "Failed to start tracking: \(error.localizedDescription)"
            return
        }

        await telemetry.connect()
        videoManager.startAll()

        isStreamingPoses = true
        poseTask = Task { [weak self] in await self?.runPoseLoop() }
    }

    public func stop() async {
        isStreamingPoses = false
        poseTask?.cancel(); poseTask = nil
        poseCoordinator.stop()
        videoManager.stopAll()
        await telemetry.disconnect()
    }

    // MARK: - Internals

    private func requestAuthorizations() async -> Bool {
        // Both services share the same underlying permission dialog on
        // visionOS, but each one advertises what it needs.
        let handOK = await (poseCoordinator as PoseStreamCoordinator).requestHandAuthIfNeeded()
        let headOK = await (poseCoordinator as PoseStreamCoordinator).requestHeadAuthIfNeeded()
        return handOK && headOK
    }

    private func runPoseLoop() async {
        for await var frame in poseCoordinator.frames() {
            if Task.isCancelled { break }
            
            // Inject the UI's current mode into the wire packet
            frame.mode = currentMode
            
            await telemetry.send(frame)
            lastFrameSequence = frame.sequence
            lastFrame = frame
        }
    }

    private func wireObservers() {
        observerTasks.append(Task { [weak self] in
            guard let self else { return }
            for await status in telemetry.statusStream() {
                await MainActor.run { self.connection = status }
            }
        })
        observerTasks.append(Task { [weak self] in
            guard let self else { return }
            for await state in telemetry.robotStateStream() {
                await MainActor.run { self.robotState = state }
            }
        })
    }

    deinit {
        observerTasks.forEach { $0.cancel() }
    }
}

// MARK: - Auth passthrough

/// Exposed as an extension to keep `PoseStreamCoordinator` single-responsibility.
extension PoseStreamCoordinator {
    func requestHandAuthIfNeeded() async -> Bool {
        guard HandTrackingService.isSupported else { return true }
        // Re-request on every launch; the OS caches the answer.
        return await HandTrackingService().requestAuthorization()
    }
    func requestHeadAuthIfNeeded() async -> Bool {
        guard HeadTrackingService.isSupported else { return true }
        return await HeadTrackingService().requestAuthorization()
    }
}
