// WorkflowOrchestratorProtocol.swift
// HaispaceBooths — Core/Workflow
//
// Protocol Kontrak Business State Machine Workflow Orchestrator.

import Foundation

public protocol WorkflowOrchestratorProtocol: Sendable {
    
    /// Stage alur bisnis saat ini
    var currentStage: WorkflowStage { get }
    
    /// Snapshot kesehatan Workflow Engine
    var healthSnapshot: WorkflowHealth { get }
    
    /// Menangani User Intent dari SwiftUI View Layer
    func handleIntent(_ intent: WorkflowIntent) async throws
    
    /// Memproses Event dari Capability Event Bus
    func processEvent(_ envelope: EventEnvelope<Data>) async throws
    
    /// Reset Workflow ke Landing Standby State
    func resetToLanding() async
}
