//
//  CameraID.swift
//  MabelTeleop
//

import Foundation

public enum CameraID: String, CaseIterable, Codable, Sendable, Identifiable {
    case main
    case leftWrist  = "left_wrist"
    case rightWrist = "right_wrist"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .main:       return "Main"
        case .leftWrist:  return "Left Wrist"
        case .rightWrist: return "Right Wrist"
        }
    }
}
