//
//  ConfigurationLoader.swift
//  MabelTeleop
//
//  Loads `AppConfiguration` at runtime from a bundled `Config.plist`,
//  falling back to `AppConfiguration.default` if the plist is missing
//  or malformed. This lets you ship one binary and reconfigure per
//  robot by swapping the plist, without a rebuild.
//
//  Expected plist layout (all keys optional — missing values use defaults):
//
//  <plist>
//    <dict>
//      <key>network</key>
//      <dict>
//        <key>host</key>                 <string>mabel.local</string>
//        <key>telemetryPort</key>        <integer>9090</integer>
//        <key>telemetryPath</key>        <string>/teleop</string>
//        <key>videoPort</key>            <integer>8080</integer>
//        <key>mainCameraPath</key>       <string>/camera/main/stream.mjpg</string>
//        <key>leftWristCameraPath</key>  <string>/camera/wrist_left/stream.mjpg</string>
//        <key>rightWristCameraPath</key> <string>/camera/wrist_right/stream.mjpg</string>
//      </dict>
//      <key>tracking</key>
//      <dict>
//        <key>transmissionRateHz</key>     <real>60</real>
//        <key>sendFullSkeleton</key>       <true/>
//        <key>minTrackingConfidence</key>  <real>0.5</real>
//      </dict>
//      <key>video</key>
//      <dict>
//        <key>wristThumbnailWidth</key>  <integer>480</integer>
//        <key>reconnectDelay</key>       <real>1.5</real>
//      </dict>
//    </dict>
//  </plist>
//

import Foundation
import OSLog

public enum ConfigurationLoader {

    private static let log = Logger(subsystem: "com.mabel.teleop", category: "config")

    /// Looks up `Config.plist` in the given bundle and merges any values
    /// it finds on top of `AppConfiguration.default`.
    public static func load(
        from bundle: Bundle = .main,
        resource: String = "Config",
        fallback: AppConfiguration = .default
    ) -> AppConfiguration {
        guard
            let url = bundle.url(forResource: resource, withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let raw = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else {
            log.info("Config.plist not found — using defaults")
            return fallback
        }
        return merge(fallback, with: raw)
    }

    // MARK: - Merge

    private static func merge(
        _ base: AppConfiguration,
        with raw: [String: Any]
    ) -> AppConfiguration {
        var cfg = base

        if let net = raw["network"] as? [String: Any] {
            cfg.network.host                = net["host"]                as? String ?? cfg.network.host
            cfg.network.telemetryPort       = net["telemetryPort"]       as? Int    ?? cfg.network.telemetryPort
            cfg.network.telemetryPath       = net["telemetryPath"]       as? String ?? cfg.network.telemetryPath
            cfg.network.videoPort           = net["videoPort"]           as? Int    ?? cfg.network.videoPort
            cfg.network.mainCameraPath      = net["mainCameraPath"]      as? String ?? cfg.network.mainCameraPath
            cfg.network.leftWristCameraPath = net["leftWristCameraPath"] as? String ?? cfg.network.leftWristCameraPath
            cfg.network.rightWristCameraPath = net["rightWristCameraPath"] as? String ?? cfg.network.rightWristCameraPath
        }

        if let track = raw["tracking"] as? [String: Any] {
            if let rate  = track["transmissionRateHz"]  as? Double { cfg.tracking.transmissionRateHz  = rate }
            if let full  = track["sendFullSkeleton"]    as? Bool   { cfg.tracking.sendFullSkeleton    = full }
            if let conf  = track["minTrackingConfidence"] as? Double {
                cfg.tracking.minTrackingConfidence = Float(conf)
            }
        }

        if let video = raw["video"] as? [String: Any] {
            if let w = video["wristThumbnailWidth"] as? Int    { cfg.video.wristThumbnailWidth = w }
            if let d = video["reconnectDelay"]      as? Double { cfg.video.reconnectDelay      = d }
        }

        log.info("Loaded config host=\(cfg.network.host, privacy: .public) rate=\(cfg.tracking.transmissionRateHz)Hz")
        return cfg
    }
}
