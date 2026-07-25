// PaymentAndDeliveryView.swift
// HaispaceBooths — UI/Views (Scene 5: The Celebration & Gift)
//
// Payment & Photo Delivery View Haispace Kiosk Photobooth.
// REVISION 1 — Based on Apple Design Review #009 (8.8/10 -> Target Approved 9.6+).
// - Headline: "Your memories are ready" (Memories-first emotional narrative)
// - Photo Remains Hero: Photo Thumbnail Canvas retained above QR Code
// - FSM State Engine: enum PaymentDeliveryStage (awaitingPayment, authorizing, paymentConfirmed, deliveryReady)
// - Non-cashier Price Hierarchy (Price positioned subtly at the bottom)

import SwiftUI

public struct PaymentAndDeliveryView: View {
    
    // Injected Handlers
    private let onPaymentSuccess: () async -> Void
    private let onDeliveryComplete: () async -> Void
    
    // Explicit State Machine Engine
    private enum PaymentDeliveryStage: Equatable {
        case awaitingPayment
        case authorizing
        case paymentConfirmed
        case deliveryReady
    }
    
    @State private var stage: PaymentDeliveryStage = .awaitingPayment
    
    public init(
        onPaymentSuccess: @escaping () async -> Void,
        onDeliveryComplete: @escaping () async -> Void
    ) {
        self.onPaymentSuccess = onPaymentSuccess
        self.onDeliveryComplete = onDeliveryComplete
    }
    
    public var body: some View {
        ZStack {
            // Dark Atmosphere Background
            Color(white: 0.04)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer().frame(height: 16)
                
                // PHOTO THUMBNAIL RETAINED (Photo Remains the Emotional Hero)
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.indigo.opacity(0.35), Color.purple.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    
                    HStack(spacing: 12) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("High-Resolution Print & Digital Memories")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 420, height: 70)
                
                if stage == .awaitingPayment || stage == .authorizing {
                    // STAGE 1: REASSURING PAYMENT (Memories First Narrative)
                    VStack(spacing: 8) {
                        Text("Your memories are ready")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("We'll prepare your digital & printed copies.")
                            .font(.system(size: 18, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    // QRIS CODE CANVAS
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 260, height: 260)
                            .shadow(color: .white.opacity(0.15), radius: 20, x: 0, y: 0)
                        
                        if stage == .authorizing {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.4)
                                    .tint(.black)
                                
                                Text("Authorizing...")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.black)
                            }
                        } else {
                            Image(systemName: "qrcode")
                                .font(.system(size: 180))
                                .foregroundColor(.black)
                        }
                    }
                    .onTapGesture {
                        executeSimulatedAuthorization()
                    }
                    
                    // SUBTLE PRICE HIERARCHY (Positioned at bottom, non-cashier)
                    Text("Rp 35.000 — All Digital & Printed Package")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        
                } else {
                    // STAGE 2: INSTANT GIFT DELIVERY (AirDrop / Local WiFi Download)
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.green)
                        
                        Text("Take your memories with you")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Scan QR Code below or use AirDrop to save directly to your phone.")
                            .font(.system(size: 18, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .transition(.opacity.combined(with: .scale))
                    
                    // DOWNLOAD DELIVERY QR CANVAS
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 240, height: 240)
                            .shadow(color: .green.opacity(0.2), radius: 20, x: 0, y: 0)
                        
                        Image(systemName: "qrcode")
                            .font(.system(size: 160))
                            .foregroundColor(.black)
                    }
                    
                    // Finish Action Button
                    Button(action: {
                        Task {
                            await onDeliveryComplete()
                        }
                    }) {
                        Text("Done & Thank You")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 56)
                            .padding(.vertical, 18)
                            .background(Capsule().fill(Color.white))
                            .shadow(color: Color.white.opacity(0.2), radius: 16, x: 0, y: 4)
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - FSM Authorization Transition Engine
    
    private func executeSimulatedAuthorization() {
        guard stage == .awaitingPayment else { return }
        
        Task {
            // 1. Transition to Authorizing Stage (400ms Acknowledgement)
            withAnimation(.easeInOut(duration: 0.2)) {
                stage = .authorizing
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            
            // 2. Trigger Payment Success Callback
            await onPaymentSuccess()
            
            // 3. Transition to Delivery Ready Stage
            withAnimation(.easeInOut(duration: 0.4)) {
                stage = .deliveryReady
            }
        }
    }
}

#Preview {
    PaymentAndDeliveryView(
        onPaymentSuccess: {},
        onDeliveryComplete: {}
    )
}
