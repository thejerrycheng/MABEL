//
//  DashboardView.swift
//  MabelTeleop
//
//  Right-hand status panel. Pure presentation — all derivation lives
//  in DashboardViewModel.
//

import SwiftUI

struct DashboardView: View {

    @ObservedObject var viewModel: DashboardViewModel
    @Binding var immersiveOpen: Bool
    let onToggleImmersive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusSection
            controlsSection
            diagnosticsSection
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text("Mabel Teleop")
                .font(.title2.weight(.semibold))
            Spacer()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Link")
            StatusPill(
                label: "Status",
                value: viewModel.connectionText,
                color: viewModel.connectionColor
            )
            HStack(spacing: 8) {
                StatusPill(label: "Mode", value: viewModel.modeText, color: .blue)
                StatusPill(label: "Latency", value: viewModel.latencyText, color: .orange)
            }
            StatusPill(label: "Battery", value: viewModel.batteryText, color: .green)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Controls")
            HStack(spacing: 10) {
                if viewModel.isRunning {
                    Button(role: .destructive, action: viewModel.stop) {
                        Label("Stop Teleop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button(action: viewModel.start) {
                        Label("Start Teleop", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Button(action: onToggleImmersive) {
                Label(
                    immersiveOpen ? "Exit Immersive" : "Enter Immersive",
                    systemImage: immersiveOpen ? "visionpro.slash" : "visionpro"
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if !viewModel.diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Diagnostics")
                ForEach(viewModel.diagnostics) { diag in
                    DiagnosticRow(diagnostic: diag)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1.0)
    }
}

// MARK: - Diagnostic row

private struct DiagnosticRow: View {
    let diagnostic: RobotState.Diagnostic

    private var icon: String {
        switch diagnostic.level {
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }
    private var color: Color {
        switch diagnostic.level {
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.component).font(.caption.weight(.semibold))
                Text(diagnostic.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
