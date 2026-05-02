//
//  MJPEGVideoStream.swift
//  MabelTeleop
//
//  Consumes an HTTP multipart/x-mixed-replace (MJPEG) stream from the
//  robot and publishes decoded UIImages frame-by-frame. MJPEG is chosen
//  over WebRTC for the first cut because most ROS-side camera servers
//  (e.g. cv_camera, web_video_server) expose it natively and latency is
//  < 100ms on a LAN.
//
//  If/when we move to WebRTC, just add a new `VideoStream` conformer
//  and swap it in via the `StreamManager`.
//

import Foundation
import UIKit
import OSLog

public protocol VideoStream: AnyObject, Sendable {
    var id: CameraID { get }
    func frames() -> AsyncStream<UIImage>
    func start()
    func stop()
}

public final class MJPEGVideoStream: NSObject, VideoStream, @unchecked Sendable {

    public let id: CameraID
    private let url: URL
    private let reconnectDelay: TimeInterval
    private let log = Logger(subsystem: "com.mabel.teleop", category: "mjpeg")

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var isRunning = false
    private let buffer = FrameBuffer()
    private let continuations = Continuations()

    public init(id: CameraID, url: URL, reconnectDelay: TimeInterval = 1.5) {
        self.id = id
        self.url = url
        self.reconnectDelay = reconnectDelay
    }

    public func frames() -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            let token = continuations.add(continuation)
            continuation.onTermination = { [weak self] _ in
                self?.continuations.remove(token)
            }
        }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = .infinity
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.setValue("multipart/x-mixed-replace", forHTTPHeaderField: "Accept")
        task = session?.dataTask(with: request)
        task?.resume()
    }

    public func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func scheduleReconnect() {
        guard isRunning else { return }
        let delay = reconnectDelay
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning else { return }
            self.log.info("reconnecting \(self.id.rawValue, privacy: .public)")
            self.stop()
            self.isRunning = true   // stop flipped it false
            self.start()
        }
    }
}

// MARK: - URLSession delegates

extension MJPEGVideoStream: URLSessionDataDelegate {

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        buffer.append(data)
        while let jpeg = buffer.extractNextJPEG() {
            guard let image = UIImage(data: jpeg) else { continue }
            continuations.yield(image)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            log.error("stream error \(self.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        scheduleReconnect()
    }
}

// MARK: - Frame buffer

/// Scans an MJPEG byte stream for SOI (FFD8) … EOI (FFD9) markers
/// and returns each complete JPEG. Thread-safe via an internal lock.
private final class FrameBuffer {
    private var data = Data()
    private let lock = NSLock()
    private static let soi: [UInt8] = [0xFF, 0xD8]
    private static let eoi: [UInt8] = [0xFF, 0xD9]

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        // Cap buffer growth in case we never find an EOI (defensive).
        if data.count > 8 * 1024 * 1024 { data.removeFirst(data.count - 2 * 1024 * 1024) }
    }

    func extractNextJPEG() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard
            let start = data.firstRange(of: Data(Self.soi)),
            let endRange = data.range(of: Data(Self.eoi), options: [], in: start.lowerBound..<data.endIndex)
        else { return nil }

        let end = endRange.upperBound
        let frame = data.subdata(in: start.lowerBound..<end)
        data.removeSubrange(data.startIndex..<end)
        return frame
    }
}

// MARK: - Continuation fan-out

private final class Continuations: @unchecked Sendable {
    private var map: [UUID: AsyncStream<UIImage>.Continuation] = [:]
    private let lock = NSLock()

    func add(_ c: AsyncStream<UIImage>.Continuation) -> UUID {
        let id = UUID()
        lock.lock(); defer { lock.unlock() }
        map[id] = c
        return id
    }

    func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        map.removeValue(forKey: id)
    }

    func yield(_ image: UIImage) {
        lock.lock()
        let values = Array(map.values)
        lock.unlock()
        for c in values { c.yield(image) }
    }
}
