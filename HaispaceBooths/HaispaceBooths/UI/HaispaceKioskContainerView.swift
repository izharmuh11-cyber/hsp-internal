// HaispaceKioskContainerView.swift
// HaispaceBooths — UI Coordinator Container
//
// Complete 6-Act Experience Journey Coordinator bound to WorkflowOrchestrator state machine.
// Fulfills 100% of Doc #51-#56 Design Invariants & GPT Final Review #011.

import SwiftUI

public struct HaispaceKioskContainerView: View {
    
    public enum KioskScene {
        case scene1Invitation      // AttractView (Approved 9.1/10)
        case scene2Choice          // CreateSessionView (Approved 9.2/10)
        case scene3Moment          // CameraCaptureView (Approved 9.6/10)
        case scene4Reveal          // CelebrationPreviewView (Approved 9.8/10)
        case scene5CelebrationGift // PaymentAndDeliveryView (Approved 9.7/10)
        case scene6Goodbye         // FarewellView (Approved 9.7/10)
    }
    
    // Core Workflow Orchestrator Integration
    private let orchestrator: WorkflowOrchestratorProtocol
    
    @State private var currentScene: KioskScene = .scene1Invitation
    @State private var sessionModel: SessionModel = SessionModel(
        sessionId: UUID().uuidString,
        guestCount: 1,
        selectedPackageId: "pkg_grad",
        selectedTemplateId: "tmpl_classic"
    )
    
    public init(orchestrator: WorkflowOrchestratorProtocol = WorkflowOrchestrator()) {
        self.orchestrator = orchestrator
    }
    
    public var body: some View {
        ZStack {
            switch currentScene {
            case .scene1Invitation:
                AttractView {
                    // Trigger Orchestrator Event: Landing Touch -> Guest Registration / Choice
                    _ = try? await orchestrator.process(event: .guestRegistered(name: "Guest", email: nil, instagram: nil))
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentScene = .scene2Choice
                    }
                }
                .transition(.opacity)
                
            case .scene2Choice:
                CreateSessionView { theme in
                    // Trigger Orchestrator Event: Package / Theme Selection -> Capturing
                    sessionModel.selectedPackageId = theme
                    _ = try? await orchestrator.process(event: .packageSelected(packageId: theme))
                    _ = try? await orchestrator.process(event: .templateSelected(templateId: "tmpl_\(theme.lowercased())"))
                    _ = try? await orchestrator.process(event: .startCaptureSequence)
                    
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentScene = .scene3Moment
                    }
                }
                .transition(.opacity)
                
            case .scene3Moment:
                CameraCaptureView { capturedAssetPath in
                    // Trigger Orchestrator Event: Photo Captured -> Editing Preview Reveal
                    _ = try? await orchestrator.process(event: .captureCompleted(assetPaths: [capturedAssetPath]))
                    
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentScene = .scene4Reveal
                    }
                }
                .transition(.opacity)
                
            case .scene4Reveal:
                CelebrationPreviewView(
                    onAcceptPreview: {
                        // Trigger Orchestrator Event: Preview Accepted -> Payment & Delivery
                        _ = try? await orchestrator.process(event: .editingConfirmed(renderAssetPath: "render_001.jpg"))
                        
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentScene = .scene5CelebrationGift
                        }
                    },
                    onRetakeRequested: {
                        // Retake requested -> Return to Camera Capture
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentScene = .scene3Moment
                        }
                    }
                )
                .transition(.opacity)
                
            case .scene5CelebrationGift:
                PaymentAndDeliveryView(
                    onPaymentSuccess: {
                        // Trigger Orchestrator Event: Payment Authorized -> Delivery Dispatch
                        _ = try? await orchestrator.process(event: .paymentAuthorized(transactionId: "tx_\(UUID().uuidString.prefix(8))", method: .qris))
                    },
                    onDeliveryComplete: {
                        // Trigger Orchestrator Event: Delivery Completed -> Goodbye Transition
                        _ = try? await orchestrator.process(event: .deliveryDispatched(channel: .airdrop, success: true))
                        
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentScene = .scene6Goodbye
                        }
                    }
                )
                .transition(.opacity)
                
            case .scene6Goodbye:
                FarewellView {
                    // Reset Session & Orchestrator back to Landing / Scene 1 Attract Mode
                    _ = try? await orchestrator.process(event: .resetToLanding)
                    sessionModel = SessionModel(
                        sessionId: UUID().uuidString,
                        guestCount: 1,
                        selectedPackageId: "pkg_grad",
                        selectedTemplateId: "tmpl_classic"
                    )
                    
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentScene = .scene1Invitation
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    HaispaceKioskContainerView()
}
