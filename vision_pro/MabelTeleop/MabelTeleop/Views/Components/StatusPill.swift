//
//  StatusPill.swift
//  MabelTeleop
//

import SwiftUI

public struct StatusPill: View {
    public let label: String
    public let value: String
    public var color: Color = .accentColor

    public var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
