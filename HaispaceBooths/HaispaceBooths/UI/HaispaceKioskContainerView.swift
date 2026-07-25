// HaispaceKioskContainerView.swift
// HaispaceBooths — UI Coordinator Container
//
// Complete 6-Act Experience Journey Coordinator.
// Fulfills 100% of Doc #51-#56 Design Invariants & GPT Final Review #011.
//
// NOTE: Entry point utama app menggunakan RootView + AppState (ADR-001).
// HaispaceKioskContainerView adalah standalone UI container yang digunakan
// untuk preview dan pengembangan isolated tanpa coupling ke WorkflowOrchestrator.

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

    @State private var currentScene: KioskScene = .scene1Invitation

    public init() {}

    public var body: some View {
        ZStack {
            switch currentScene {
            case .scene1Invitation:
                AttractView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentScene = .scene2Choice
                    }
                }
                .transition(.opacity)

            case .scene2Choice:
                CreateSessionView { _ in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentScene = .scene3Moment
                    }
                }
                .transition(.opacity)

            case .scene3Moment:
                CameraCaptureView { _ in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        currentScene = .scene4Reveal
                    }
                }
                .transition(.opacity)

            case .scene4Reveal:
                CelebrationPreviewView(
                    onAcceptPreview: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentScene = .scene5CelebrationGift
                        }
                    },
                    onRetakeRequested: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentScene = .scene3Moment
                        }
                    }
                )
                .transition(.opacity)

            case .scene5CelebrationGift:
                PaymentAndDeliveryView(
                    onPaymentSuccess: {
                        // Payment success — delivery akan trigger scene 6
                    },
                    onDeliveryComplete: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentScene = .scene6Goodbye
                        }
                    }
                )
                .transition(.opacity)

            case .scene6Goodbye:
                FarewellView(onResetToAttractMode: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentScene = .scene1Invitation
                    }
                })
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    HaispaceKioskContainerView()
}
