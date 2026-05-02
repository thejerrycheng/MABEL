//
//  DashboardViewModel.swift
//  MabelTeleop
//
//  Thin view model that derives UI-ready values from a TeleopSession.
//  Keeps SwiftUI views free of formatting / derivation logic.
//

import Foundation
import SwiftUI
import Combine

@MainActor
public final class DashboardViewModel: ObservableObject {

    private let session: TeleopSession
    private var bag: Set<AnyCancellable> = []

    @Published public private(set) var connectionText: String = ""
    @Published public private(set) var connectionColor: Color = .secondary
    @Published public private(set) var batteryText: String = "—"
    @Published public private(set) var latencyText: String = "—"
    @Published public private(set) var modeText: String = "Idle"
    @Published public private(set) var diagnostics: [RobotState.Diagnostic] = []

    public init(session: TeleopSession) {
        self.session = session
        bind()
    }

    public var isRunning: Bool { session.isStreamingPoses }

    public func start() { Task { await session.start() } }
    public func stop()  { Task { await session.stop()  } }

    // MARK: - Binding

    private func bind() {
        session.$connection
            .sink { [weak self] in self?.apply(connection: $0) }
            .store(in: &bag)

        session.$robotState
            .sink { [weak self] in self?.apply(state: $0) }
            .store(in: &bag)
    }

    private func apply(connection: ConnectionStatus) {
        connectionText = connection.displayText
        switch connection {
        case .connected:     connectionColor = .green
        case .connecting:    connectionColor = .yellow
        case .disconnected:  connectionColor = .secondary
        case .failed:        connectionColor = .red
        }
    }

    private func apply(state: RobotState) {
        modeText = state.mode.rawValue.capitalized
        if let battery = state.battery {
            let pct = Formatters.percent.string(from: NSNumber(value: battery.percentage)) ?? "—"
            let volt = Formatters.voltage.string(from: NSNumber(value: battery.voltage)) ?? "—"
            batteryText = "\(pct) · \(volt) V"
        } else {
            batteryText = "—"
        }
        if let ms = state.latencyMs {
            latencyText = (Formatters.latencyMs.string(from: NSNumber(value: ms)) ?? "—") + " ms"
        } else {
            latencyText = "—"
        }
        diagnostics = state.diagnostics
    }
}
