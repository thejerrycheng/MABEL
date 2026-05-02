//
//  ConnectionStatus.swift
//  MabelTeleop
//

import Foundation

public enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(reason: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .disconnected:            return "Disconnected"
        case .connecting:              return "Connecting…"
        case .connected:               return "Connected"
        case .failed(let reason):      return "Failed: \(reason)"
        }
    }
}
