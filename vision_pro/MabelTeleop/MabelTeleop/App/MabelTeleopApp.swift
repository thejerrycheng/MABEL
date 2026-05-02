//
//  MabelTeleopApp.swift
//  MabelTeleop
//
//  App entry point. Declares one main window (the operator dashboard)
//  and one immersive space (for in-situ pose visualization / debug).
//  The TeleopSession is created here and injected via environment so
//  both scenes share the same state.
//

import SwiftUI

@main
struct MabelTeleopApp: App {

    @StateObject private var session: TeleopSession

    init() {
        let config = ConfigurationLoader.load()
        _session = StateObject(wrappedValue: TeleopSession(configuration: config))
    }

    var body: some Scene {
        // Primary 2D operator window: cameras + status HUD.
        WindowGroup("Mabel Teleop", id: WindowID.main.rawValue) {
            ContentView()
                .environmentObject(session)
                .environmentObject(session.videoManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1400, height: 900)

        // Optional immersive space for debugging hand skeleton retargeting.
        ImmersiveSpace(id: WindowID.immersive.rawValue) {
            TeleopImmersiveSpace()
                .environmentObject(session)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

/// Centralized window / immersive-space identifiers.
enum WindowID: String {
    case main      = "main-window"
    case immersive = "immersive-teleop"
}
