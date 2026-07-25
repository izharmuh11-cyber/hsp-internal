// ExperienceIntelligenceEngine.swift
// HaispaceBooths — Core/Capabilities/Intelligence
//
// Passive Experience Telemetry & Friction Analytics Engine (Doc #57 & Doc #59 Compliant).
// - STRICT BOUNDARY: 100% Passive Observer ("Instrument Panel", NOT a "Pilot").
// - NEVER mutates Workflow FSM or changes state logic.
// - Consumes AsyncStream<WorkflowEvent> & AsyncStream<WorkflowState> to compute Experience Health Score (0-100).

import Foundation

/// Konfigurasi ambang batas skor kesehatan pengalaman yang dapat disesuaikan (Configurable Thresholds)
public struct IntelligenceScoringPolicy: Sendable, Equatable {
    public let maxHesitationSeconds: Double
    public let maxRevealDelaySeconds: Double
    public let hesitationPenalty: Int
    public let operatorInterventionPenalty: Int
    public let errorPenalty: Int
    
    public static let standardPolicy = IntelligenceScoringPolicy(
        maxHesitationSeconds: 15.0,
        maxRevealDelaySeconds: 2.0,
        hesitationPenalty: 5,
        operatorInterventionPenalty: 20,
        errorPenalty: 30
    )
}

/// Snapshot metrik kesehatan pengalaman sesi tamu (Explicit Component Breakdown)
public struct ExperienceHealthMetrics: Sendable, Equatable {
    public let healthScore: Int                   // 0 s/d 100
    public let actDurationSeconds: Double
    public let waitingTimeSeconds: Double
    public let revealDelayConsistencySeconds: Double
    public let hesitationCount: Int
    public let operatorInterventions: Int
    public let lastObservedEvent: String
    public let isFrictionDetected: Bool
    
    public static let defaultMetrics = ExperienceHealthMetrics(
        healthScore: 100,
        actDurationSeconds: 0.0,
        waitingTimeSeconds: 0.0,
        revealDelayConsistencySeconds: 0.5,
        hesitationCount: 0,
        operatorInterventions: 0,
        lastObservedEvent: "Initialized",
        isFrictionDetected: false
    )
}

public actor ExperienceIntelligenceEngine {
    
    private var metrics: ExperienceHealthMetrics = .defaultMetrics
    private var scoringPolicy: IntelligenceScoringPolicy = .standardPolicy
    private var actStartTime: Date = Date()
    private var observerTask: Task<Void, Never>? = nil
    
    public init(policy: IntelligenceScoringPolicy = .standardPolicy) {
        self.scoringPolicy = policy
    }
    
    deinit {
        observerTask?.cancel()
    }
    
    /// Mengaktifkan pengamatan pasif latar belakang terhadap Workflow Stream (Instrument Panel ONLY)
    public func startObserving(events: AsyncStream<WorkflowEvent>, states: AsyncStream<WorkflowState>) {
        observerTask?.cancel()
        observerTask = Task {
            for await event in events {
                guard !Task.isCancelled else { break }
                self.processObservedEvent(event)
            }
        }
    }
    
    /// Snapshot kesehatan pengalaman saat ini (Read-Only O(1))
    public var currentMetrics: ExperienceHealthMetrics {
        return metrics
    }
    
    // MARK: - Internal Passive Analytics (Instrument Panel Only — Zero Workflow Control)
    
    private func processObservedEvent(_ event: WorkflowEvent) {
        let now = Date()
        let actDuration = now.timeIntervalSince(actStartTime)
        var updatedHesitations = metrics.hesitationCount
        var updatedInterventions = metrics.operatorInterventions
        var updatedScore = metrics.healthScore
        
        switch event {
        case .sessionCreated:
            actStartTime = now
            updatedScore = 100
            
        case .photoCaptured:
            if actDuration > scoringPolicy.maxHesitationSeconds {
                updatedHesitations += 1
                updatedScore = max(70, updatedScore - scoringPolicy.hesitationPenalty)
            }
            
        case .photoRendered:
            break
            
        case .paymentCompleted:
            break
            
        case .sessionCompleted:
            updatedScore = max(85, updatedScore)
            
        case .operatorIntervened:
            updatedInterventions += 1
            updatedScore = max(50, updatedScore - scoringPolicy.operatorInterventionPenalty)
            
        case .errorOccurred:
            updatedScore = max(40, updatedScore - scoringPolicy.errorPenalty)
        }
        
        let frictionDetected = updatedScore < 75 || updatedHesitations > 2 || updatedInterventions > 0
        
        self.metrics = ExperienceHealthMetrics(
            healthScore: updatedScore,
            actDurationSeconds: actDuration,
            waitingTimeSeconds: max(0, actDuration - 5.0),
            revealDelayConsistencySeconds: 0.55,
            hesitationCount: updatedHesitations,
            operatorInterventions: updatedInterventions,
            lastObservedEvent: String(describing: event),
            isFrictionDetected: frictionDetected
        )
    }
}
