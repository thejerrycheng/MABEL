//
//  VideoStreamManager.swift
//  MabelTeleop
//
//  Owns one `VideoStream` per camera and exposes a single API the UI
//  layer can observe. Lifecycle is tied to the main session — call
//  `startAll()` when teleop begins, `stopAll()` when it ends.
//

import Foundation
import Combine
import UIKit

@MainActor
public final class VideoStreamManager: ObservableObject {

    @Published public private(set) var latestFrames: [CameraID: UIImage] = [:]

    private var streams: [CameraID: VideoStream] = [:]
    private var observers: [CameraID: Task<Void, Never>] = [:]

    public init(configuration: AppConfiguration) {
        for camera in CameraID.allCases {
            let stream = MJPEGVideoStream(
                id: camera,
                url: configuration.network.videoURL(for: camera),
                reconnectDelay: configuration.video.reconnectDelay
            )
            streams[camera] = stream
        }
    }

    public func startAll() {
        for (id, stream) in streams {
            stream.start()
            observers[id]?.cancel()
            observers[id] = Task { [weak self] in
                for await image in stream.frames() {
                    await MainActor.run {
                        self?.latestFrames[id] = image
                    }
                }
            }
        }
    }

    public func stopAll() {
        for task in observers.values { task.cancel() }
        observers.removeAll()
        for stream in streams.values { stream.stop() }
        latestFrames.removeAll()
    }

    public func stream(for camera: CameraID) -> VideoStream? {
        streams[camera]
    }
}
