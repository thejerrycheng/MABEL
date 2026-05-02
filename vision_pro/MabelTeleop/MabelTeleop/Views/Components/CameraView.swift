//
//  CameraView.swift
//  MabelTeleop
//
//  SwiftUI view bound to one camera feed. Chooses resampling quality
//  based on the `quality` parameter — the wrist thumbnails can afford
//  low-quality scaling, the main view should use high.
//

import SwiftUI
import UIKit

public struct CameraView: View {

    public enum Quality {
        case low, high
    }

    @EnvironmentObject private var videoManager: VideoStreamManager
    private let camera: CameraID
    private let quality: Quality

    public init(camera: CameraID, quality: Quality = .high) {
        self.camera = camera
        self.quality = quality
    }

    public var body: some View {
        ZStack {
            Color.black
            if let image = videoManager.latestFrames[camera] {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(quality == .high ? .high : .low)
                    .scaledToFit()
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.1), value: image)
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for \(camera.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            labelOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var labelOverlay: some View {
        VStack {
            HStack {
                Text(camera.displayName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
            Spacer()
        }
        .padding(10)
    }
}
