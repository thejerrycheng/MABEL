//
//  ContentView.swift
//  MabelTeleop
//

import SwiftUI


struct ContentView: View {
    @EnvironmentObject private var session: TeleopSession
    @Environment(\.openImmersiveSpace)    private var openImmersive
    @Environment(\.dismissImmersiveSpace) private var dismissImmersive
    
    @State private var immersiveOpen = false
    @State private var isSidebarVisible = true
    @State private var currentMode: TeleopMode = .manipulation

    var body: some View {
        HStack(spacing: 16) {
            
            // MARK: - Camera & Overlay Stack
            ZStack {
                // Main Background Camera
                CameraView(camera: .main, quality: .high)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                
                // Top Overlaid Wrist Cameras
                VStack {
                    HStack(spacing: 20) {
                        CameraView(camera: .leftWrist, quality: .low)
                            .frame(width: 320, height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        
                        Spacer()
                        
                        CameraView(camera: .rightWrist, quality: .low)
                            .frame(width: 320, height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    }
                    .padding(24)
                    Spacer()
                }
                
                // Bottom Floating Toolbar
                VStack {
                    Spacer()
                    HStack {
                        // Drone-Style Mode Switcher
                        Picker("Control Mode", selection: $currentMode) {
                            ForEach(TeleopMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        
                        Spacer()
                        
                        // Sidebar Toggle Button
                        Button(action: toggleSidebar) {
                            Image(systemName: isSidebarVisible ? "sidebar.right" : "sidebar.right")
                                .font(.title3)
                                .padding(14)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSidebarVisible)
            
            // MARK: - Dashboard Sidebar
            if isSidebarVisible {
                HostDashboardView(
                    session: session,
                    immersiveOpen: $immersiveOpen,
                    onToggleImmersive: toggleImmersive
                )
                .frame(width: 340)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        // Inform the Session when the mode changes so it can tag the outbound frames
        .onChange(of: currentMode) { _, newMode in
            // Assuming you add `currentMode` to TeleopSession
            // session.currentMode = newMode
        }
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isSidebarVisible.toggle()
        }
    }

    private func toggleImmersive() {
        Task { @MainActor in
            if immersiveOpen {
                await dismissImmersive()
                immersiveOpen = false
            } else {
                let result = await openImmersive(id: WindowID.immersive.rawValue)
                if case .opened = result { immersiveOpen = true }
            }
        }
    }
}

// MARK: - Host Dashboard Wrapper
private struct HostDashboardView: View {
    @StateObject private var dashboardVM: DashboardViewModel
    @Binding var immersiveOpen: Bool
    let onToggleImmersive: () -> Void

    init(session: TeleopSession, immersiveOpen: Binding<Bool>, onToggleImmersive: @escaping () -> Void) {
        _dashboardVM = StateObject(wrappedValue: DashboardViewModel(session: session))
        _immersiveOpen = immersiveOpen
        self.onToggleImmersive = onToggleImmersive
    }

    var body: some View {
        DashboardView(
            viewModel: dashboardVM,
            immersiveOpen: $immersiveOpen,
            onToggleImmersive: onToggleImmersive
        )
    }
}
