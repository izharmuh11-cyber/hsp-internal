// PaymentStore.swift
// HaispaceBooths — Core/State
//
// Store untuk status pembayaran sesi aktif.
// Mendukung QRIS (offline EMVCo generator) dan Cash.
//
// Ref: docs/design/09_payment.md
// Ref: docs/design/33_local_qris.md — QRIS offline generator

import Foundation
import Observation

// MARK: - PaymentMethod

enum PaymentMethod: String, CaseIterable {
    case qris   = "QRIS"
    case cash   = "CASH"

    var displayName: String {
        switch self {
        case .qris: return "QRIS"
        case .cash: return "Tunai"
        }
    }

    var iconName: String {
        switch self {
        case .qris: return "qrcode"
        case .cash: return "banknote"
        }
    }
}

// MARK: - PaymentStatus

enum PaymentStatus: Equatable {
    case idle               // Belum ada proses pembayaran
    case generatingQRIS     // Sedang generate QRIS offline
    case waitingForPayment  // Menunggu scan/konfirmasi
    case verifying          // Sedang verifikasi pembayaran
    case paid               // LUNAS
    case timeout            // 3 menit habis — masuk escrow
    case failed(String)     // Gagal dengan alasan
    case cancelled          // Dibatalkan operator

    var displayText: String {
        switch self {
        case .idle: return "Pilih Metode Pembayaran"
        case .generatingQRIS: return "Membuat Kode QRIS..."
        case .waitingForPayment: return "Menunggu Pembayaran"
        case .verifying: return "Memverifikasi..."
        case .paid: return "Pembayaran Diterima ✓"
        case .timeout: return "Waktu Habis"
        case .failed(let reason): return "Gagal: \(reason)"
        case .cancelled: return "Dibatalkan"
        }
    }

    var isPending: Bool {
        switch self {
        case .generatingQRIS, .waitingForPayment, .verifying: return true
        default: return false
        }
    }
}

// MARK: - PaymentStore

@Observable
final class PaymentStore {

    // MARK: State
    var status: PaymentStatus = .idle
    var selectedMethod: PaymentMethod?
    var amount: Int = 0          // Dalam Rupiah

    // QRIS state
    var qrisPayload: String?     // Raw QRIS string untuk di-encode ke QR code
    var qrisExpiresAt: Date?     // QR valid selama 3 menit
    var transactionId: String?   // ID referensi untuk idempotency

    // Cash state — audit log
    var cashConfirmedAt: Date?
    var cashConfirmedByOperatorId: String?

    // Timer state
    var remainingSeconds: Int = 180  // 3 menit countdown QRIS

    // MARK: Computed

    var isPaid: Bool {
        if case .paid = status { return true }
        return false
    }

    var isQRISExpired: Bool {
        guard let expiry = qrisExpiresAt else { return false }
        return Date() > expiry
    }

    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "Rp \(amount)"
    }

    // MARK: - Actions

    /// Set jumlah yang harus dibayar dan buat transaction ID
    @MainActor
    func preparePayment(amount: Int, method: PaymentMethod) {
        self.amount = amount
        self.selectedMethod = method
        self.transactionId = UUID().uuidString
        self.status = .idle

        if method == .qris {
            generateQRIS()
        }
    }

    /// Generate QRIS payload offline (EMVCo CRC16)
    @MainActor
    func generateQRIS() {
        status = .generatingQRIS

        Task {
            do {
                let payload = try QRISGeneratorService.generate(
                    amount: self.amount,
                    transactionId: self.transactionId ?? UUID().uuidString
                )

                await MainActor.run {
                    self.qrisPayload = payload
                    self.qrisExpiresAt = Date().addingTimeInterval(180) // 3 menit
                    self.remainingSeconds = 180
                    self.status = .waitingForPayment
                }
                HaispaceLogger.info("QRIS generated — transaction: \(String(describing: self.transactionId))", category: "payment")
            } catch {
                HaispaceLogger.error(error)
                await MainActor.run {
                    self.status = .failed
                }
            }
        }
    }

    /// Konfirmasi pembayaran cash oleh operator (requires PIN atau hold 2 detik)
    @MainActor
    func confirmCash(operatorId: String) {
        guard selectedMethod == .cash else { return }
        cashConfirmedAt = Date()
        cashConfirmedByOperatorId = operatorId
        status = .paid
        HaispaceLogger.info("Cash diterima — operator: \(operatorId), jumlah: \(formattedAmount)", category: "payment")
        
        // Simpan ke Ledger Offline
        let finalAmount = amount
        let finalId = transactionId ?? UUID().uuidString
        Task {
            try? await CoreDataService.shared.savePaymentTransaction(
                id: finalId,
                amount: finalAmount,
                method: "CASH",
                status: "PAID",
                sessionId: "S-\(finalId)" // Mock session ID mapping
            )
            BackgroundSyncClient.shared.triggerSync()
        }
    }

    /// Tandai pembayaran QRIS berhasil (dari polling atau webhook)
    @MainActor
    func markQRISPaid(referenceId: String) {
        status = .paid
        HaispaceLogger.info("QRIS terbayar — ref: \(referenceId)", category: "payment")
        
        // Simpan ke Ledger Offline
        let finalAmount = amount
        let finalId = transactionId ?? UUID().uuidString
        Task {
            try? await CoreDataService.shared.savePaymentTransaction(
                id: finalId,
                amount: finalAmount,
                method: "QRIS",
                status: "PAID",
                sessionId: "S-\(finalId)" // Mock session ID mapping
            )
            BackgroundSyncClient.shared.triggerSync()
        }
    }

    /// Payment timeout — foto masuk escrow
    @MainActor
    func handleTimeout() {
        status = .timeout
        HaispaceLogger.warning("Payment timeout — session masuk escrow", category: "payment")
        ErrorHandler.shared.handle(
            HaispaceError.paymentTimeout(sessionId: transactionId ?? "unknown"),
            context: .duringPayment
        )
    }

    /// Reset payment state (untuk sesi baru)
    @MainActor
    func reset() {
        status = .idle
        selectedMethod = nil
        amount = 0
        qrisPayload = nil
        qrisExpiresAt = nil
        transactionId = nil
        cashConfirmedAt = nil
        cashConfirmedByOperatorId = nil
        remainingSeconds = 180
    }
}
