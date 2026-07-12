// PaymentView.swift
// HaispaceBooths — App/Views/Guest
//
// Layar Pembayaran QRIS.
// Menampilkan QR Code yang di-generate dari QRISGeneratorService.
// Dilengkapi dengan animasi denyut nadi status pembayaran.

import SwiftUI
import CoreImage.CIFilterBuiltins

struct PaymentView: View {
    @Environment(AppState.self) private var appState
    
    private var paymentStore: PaymentStore? {
        appState.currentSession?.payment
    }
    
    // Animasi
    @State private var pulseOuter: Bool = false
    @State private var pulseInner: Bool = false
    
    var body: some View {
        ZStack {
            Color(hex: "#080810").ignoresSafeArea()
            
            if let store = paymentStore {
                VStack(spacing: 32) {
                    
                    Text("Selesaikan Pembayaran")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 40)
                    
                    // QRIS Card
                    ZStack {
                        // Background glow
                        Circle()
                            .fill(Color(hex: "#00D9A0").opacity(0.15))
                            .frame(width: 480, height: 480)
                            .scaleEffect(pulseOuter ? 1.1 : 0.9)
                            .opacity(pulseOuter ? 0 : 1)
                            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulseOuter)
                        
                        Circle()
                            .fill(Color(hex: "#00D9A0").opacity(0.2))
                            .frame(width: 400, height: 400)
                            .scaleEffect(pulseInner ? 1.05 : 0.95)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseInner)
                        
                        // White Card for QR
                        VStack(spacing: 24) {
                            Text("QRIS")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundStyle(.red) // Standard QRIS red
                            
                            if let payload = store.qrisPayload, let qrImage = generateQRCode(from: payload) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 250, height: 250)
                            } else {
                                ProgressView()
                                    .controlSize(.large)
                                    .frame(width: 250, height: 250)
                            }
                            
                            VStack(spacing: 4) {
                                Text(store.formattedAmount)
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                                
                                Text("A/N Haispace Photobooth")
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                            }
                        }
                        .padding(40)
                        .background(Color.white)
                        .cornerRadius(32)
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    }
                    .padding(.vertical, 20)
                    .onAppear {
                        pulseOuter = true
                        pulseInner = true
                    }
                    
                    // Timer & Status
                    VStack(spacing: 8) {
                        Text(store.status.displayText)
                            .font(.title3.bold())
                            .foregroundStyle(store.status == .paid ? Color(hex: "#00D9A0") : .white)
                        
                        if store.status.isPending {
                            Text("Sisa waktu: \(formatTime(store.remainingSeconds))")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(store.remainingSeconds < 60 ? .red : .white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // Operator Mock Controls (Khusus Fase MVP untuk tes cepat)
                    #if DEBUG
                    HStack(spacing: 16) {
                        Button("Mock Paid (Webhook)") {
                            withAnimation {
                                store.markQRISPaid(referenceId: "MOCK-\(Int.random(in: 1000...9999))")
                                proceedToProcessing()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .padding(.bottom, 20)
                    #endif
                }
            } else {
                Text("Error: No Payment Data")
                    .foregroundStyle(.white)
            }
            
            // Secret "Cash Diterima" Button (Pojok Kanan Bawah)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 100, height: 100)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 2.0) {
                            if let s = paymentStore, s.status.isPending {
                                s.selectedMethod = .cash
                                s.confirmCash(operatorId: appState.operatorState.currentOperator?.id ?? "unknown")
                                proceedToProcessing()
                            }
                        }
                }
            }
        }
    }
    
    private func proceedToProcessing() {
        // Pindah ke layar processing (dan eksekusi render CoreImage di sana)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring) {
                appState.navigateTo(.processing)
            }
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        if let outputImage = filter.outputImage {
            // Scale up image to be sharp
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}

#Preview {
    PaymentView()
        .environment(AppState.previewWithActiveSession)
}
