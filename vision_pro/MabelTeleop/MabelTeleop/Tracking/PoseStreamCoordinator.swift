//
//  PoseStreamCoordinator.swift
//  MabelTeleop
//
//  Fuses head and hand tracking into a single, rate-limited AsyncStream
//  of `TeleopFrame`s ready for transmission. This is the one object the
//  networking layer talks to for outbound data.
//
//  Design notes:
//  - Hand tracking is the authoritative clock: we emit a frame each time
//    the hand provider pushes an update (≤ ~90 Hz), then downsample to
//    the configured transmission rate.
//  - Head pose is *pulled* (sampled) when a frame is emitted, which keeps
//    the two sources perfectly time-aligned.
//

import Foundation

@MainActor
public final class PoseStreamCoordinator {

    private let handService: HandTrackingService
    private let headService: HeadTrackingService
    private let config: AppConfiguration.Tracking
    private var sequence: UInt64 = 0
    private var lastEmitTime: TimeInterval = 0

    public init(
        handService: HandTrackingService,
        headService: HeadTrackingService,
        config: AppConfiguration.Tracking
    ) {
        self.handService = handService
        self.headService = headService
        self.config = config
    }

    public func start() async throws {
        async let hand: () = handService.start()
        async let head: () = headService.start()
        _ = try await (hand, head)
    }

    public func stop() {
        handService.stop()
        headService.stop()
    }

    /// Emits `TeleopFrame`s rate-limited to `config.transmissionRateHz`.
    public func frames() -> AsyncStream<TeleopFrame> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                let minInterval = 1.0 / config.transmissionRateHz
                for await snapshot in handService.snapshots() {
                    let now = snapshot.timestamp
                    if now - lastEmitTime < minInterval { continue }
                    lastEmitTime = now

                    guard let head = headService.currentPose(at: now) else { continue }

                    sequence &+= 1
                    let frame = TeleopFrame(
                        sequence: sequence,
                        timestamp: now,
                        head: head,
                        leftHand: snapshot.left,
                        rightHand: snapshot.right
                    )
                    continuation.yield(frame)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
