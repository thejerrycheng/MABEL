//
//  AppConfiguration.swift
//  MabelTeleop
//
//  Central configuration for network endpoints, tracking rates,
//  and video stream parameters. Edit this file (or the shipped
//  Config.plist) to point the headset at a new robot.
//

import Foundation

public struct AppConfiguration: Sendable {

    // MARK: - Network

    public struct Network: Sendable {
        /// Host running the Mabel control stack (ROS bridge / custom server).
        public var host: String
        /// WebSocket port for bidirectional telemetry (pose out, robot state in).
        public var telemetryPort: Int
        /// Path component of the telemetry WebSocket URL.
        public var telemetryPath: String
        /// Base HTTP port for MJPEG video streams. Each camera is a subpath.
        public var videoPort: Int
        /// Sub-paths for the three camera feeds.
        public var mainCameraPath: String
        public var leftWristCameraPath: String
        public var rightWristCameraPath: String

        public var telemetryURL: URL {
            URL(string: "ws://\(host):\(telemetryPort)\(telemetryPath)")!
        }

        public func videoURL(for camera: CameraID) -> URL {
            let path: String
            switch camera {
            case .main:       path = mainCameraPath
            case .leftWrist:  path = leftWristCameraPath
            case .rightWrist: path = rightWristCameraPath
            }
            return URL(string: "http://\(host):\(videoPort)\(path)")!
        }
    }

    // MARK: - Tracking

    public struct Tracking: Sendable {
        /// Target transmission rate for pose packets (Hz).
        /// ARKit hand tracking tops out near 90 Hz; 60 is a good ceiling for retargeting.
        public var transmissionRateHz: Double
        /// Whether to transmit raw joint transforms or a reduced skeleton.
        public var sendFullSkeleton: Bool
        /// Drop frames whose hand-tracking confidence is below this threshold.
        public var minTrackingConfidence: Float
    }

    // MARK: - Video

    public struct Video: Sendable {
        /// Preferred decode size for wrist thumbnails (pixels, width).
        public var wristThumbnailWidth: Int
        /// Reconnect delay when a stream drops (seconds).
        public var reconnectDelay: TimeInterval
    }

    // MARK: - Instance

    public var network: Network
    public var tracking: Tracking
    public var video: Video

    public static let `default` = AppConfiguration(
        network: .init(
            host: "mabel.local",
            telemetryPort: 9090,
            telemetryPath: "/teleop",
            videoPort: 8080,
            mainCameraPath: "/camera/main/stream.mjpg",
            leftWristCameraPath: "/camera/wrist_left/stream.mjpg",
            rightWristCameraPath: "/camera/wrist_right/stream.mjpg"
        ),
        tracking: .init(
            transmissionRateHz: 60.0,
            sendFullSkeleton: true,
            minTrackingConfidence: 0.5
        ),
        video: .init(
            wristThumbnailWidth: 480,
            reconnectDelay: 1.5
        )
    )
}
