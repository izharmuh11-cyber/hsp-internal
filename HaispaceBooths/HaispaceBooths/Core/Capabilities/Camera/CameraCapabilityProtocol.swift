// CameraCapabilityProtocol.swift
// HaispaceBooths — Core/Capabilities/Camera

import Foundation

public struct CameraConfiguration: Codable, Sendable, Equatable {
    public let frameRate: Int
    
    public init(frameRate: Int = 30) {
        self.frameRate = frameRate
    }
}

public struct CameraMetrics: Codable, Sendable {
    public let totalCaptures: Int
    
    public init(totalCaptures: Int = 0) {
        self.totalCaptures = totalCaptures
    }
}

public protocol CameraCapabilityProtocol: Sendable {
    var healthSnapshot: CameraHealth { get async }
    var metricsSnapshot: CameraMetrics { get async }
    func prepare(configuration: CameraConfiguration) async throws
    func startSession(sessionId: SessionID) async throws
    func stopSession() async
    func requestCapture(correlationId: CorrelationID) async throws
}
