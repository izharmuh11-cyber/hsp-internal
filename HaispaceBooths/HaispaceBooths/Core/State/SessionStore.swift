// SessionStore.swift
// HaispaceBooths — Core/State
//
// Store terpenting — mengelola sesi foto yang sedang aktif.
// Satu-satunya sumber kebenaran untuk semua data sesi aktif.
//
// ATURAN:
// - `currentSession` di AppState adalah SATU-SATUNYA referensi sesi aktif
// - Tidak boleh ada sesi state di tempat lain
// - Timer sesi harus bisa di-cancel saat operator pause/end
//
// Ref: docs/design/39_state_architecture.md — SessionStore
// Ref: docs/design/40_concurrency_strategy.md — Task Cancellation

import Foundation
import Observation

// MARK: - SessionStatus

/// Status alur sesi foto tamu
enum SessionStatus {
    case briefing           // Tampilkan pose guide & countdown mulai
    case active             // Foto sedang berlangsung
    case paused             // Operator pause — timer berhenti
    case photoSelection     // Tamu pilih foto terbaik
    case frameSelection     // Tamu pilih frame overlay
    case filterSelection    // Tamu pilih LUT filter (opsional)
    case payment            // Layar pembayaran
    case processing         // Render final + upload background
    case delivery           // Layar download / AirDrop
    case completed          // Selesai — siap reset untuk tamu berikutnya

    var displayText: String {
        switch self {
        case .briefing: return "Bersiap..."
        case .active: return "Sesi Aktif"
        case .paused: return "Dijeda"
        case .photoSelection: return "Pilih Foto"
        case .frameSelection: return "Pilih Bingkai"
        case .filterSelection: return "Pilih Filter"
        case .payment: return "Pembayaran"
        case .processing: return "Memproses..."
        case .delivery: return "Ambil Foto"
        case .completed: return "Selesai"
        }
    }
}

// MARK: - SessionStore

@Observable
final class SessionStore {

    // MARK: Identity
    let sessionId: String = UUID().uuidString
    let guest: GuestInfo
    let package_: BoothPackage   // underscore karena `package` adalah keyword Swift

    // MARK: Session State
    var status: SessionStatus = .briefing
    var remainingSeconds: Int
    var currentPhotoIndex: Int = 0  // Foto ke berapa yang sedang diambil
    var isPaused: Bool = false

    // MARK: Sub-Stores
    let photos = PhotoStore()
    let payment = PaymentStore()
    let delivery = DeliveryStore()

    // MARK: Add-ons yang dipilih tamu
    var selectedAddons: Set<AddonType> = []

    // MARK: Internal — Timer Task (private untuk mencegah misuse)
    private var sessionTimerTask: Task<Void, Never>?
    private var captureTimerTask: Task<Void, Never>?

    // MARK: Computed

    var canProceedToPayment: Bool {
        photos.selectedPhotos.count >= package_.minPhotoCount
    }

    var hasSelectedMinPhotos: Bool {
        photos.selectedPhotoIds.count >= package_.minPhotoCount
    }

    var isActive: Bool {
        if case .active = status { return true }
        if case .paused = status { return true }
        return false
    }

    var progressPercentage: Double {
        let total = package_.durationSeconds
        guard total > 0 else { return 0 }
        return 1.0 - (Double(remainingSeconds) / Double(total))
    }

    // MARK: - Init

    init(package: BoothPackage, guest: GuestInfo) {
        self.package_ = package
        self.guest = guest
        self.remainingSeconds = package.durationSeconds
    }

    // MARK: - Session Control

    /// Mulai sesi — start timer countdown
    @MainActor
    func start() {
        guard status == .briefing else { return }
        status = .active
        isPaused = false
        startSessionTimer()
        HaispaceLogger.info("Sesi dimulai: \(sessionId) — Tamu: \(guest.displayName)", category: "session")
    }

    /// Pause sesi — hentikan timer (tamu tidak kehilangan waktu)
    @MainActor
    func pause() {
        guard status == .active else { return }
        status = .paused
        isPaused = true
        sessionTimerTask?.cancel()
        sessionTimerTask = nil
        HaispaceLogger.info("Sesi di-pause: \(sessionId)", category: "session")
    }

    /// Resume dari pause
    @MainActor
    func resume() {
        guard status == .paused else { return }
        status = .active
        isPaused = false
        startSessionTimer()
        HaispaceLogger.info("Sesi di-resume: \(sessionId)", category: "session")
    }

    /// Transisi ke photo selection (setelah timer habis atau semua foto diambil)
    @MainActor
    func proceedToPhotoSelection() {
        sessionTimerTask?.cancel()
        sessionTimerTask = nil
        captureTimerTask?.cancel()
        captureTimerTask = nil
        status = .photoSelection
        HaispaceLogger.info("Masuk ke photo selection — \(photos.capturedCount) foto", category: "session")
    }

    /// Transisi ke frame selection
    @MainActor
    func proceedToFrameSelection() {
        guard canProceedToPayment else { return }
        status = .frameSelection
    }

    /// Transisi ke payment
    @MainActor
    func proceedToPayment() {
        status = .payment
        let totalAmount = calculateTotalAmount()
        payment.preparePayment(amount: totalAmount, method: .qris) // Default QRIS
    }

    /// Sesi selesai — trigger background upload, siap reset
    @MainActor
    func finalize() {
        status = .completed
        HaispaceLogger.info("Sesi selesai: \(sessionId)", category: "session")

        // Trigger background cloud upload
        Task {
            await delivery.beginCloudUpload(photos: photos.finalPhotos)
        }
    }

    /// Reset paksa oleh operator (semua foto hilang)
    @MainActor
    func forceReset() {
        sessionTimerTask?.cancel()
        captureTimerTask?.cancel()
        photos.reset()
        payment.reset()
        delivery.reset()
        status = .completed
        HaispaceLogger.warning("Sesi di-force reset oleh operator: \(sessionId)", category: "session")
    }

    /// Menambahkan waktu ke timer sesi saat ini
    @MainActor
    func addTime(minutes: Int) {
        let additionalSeconds = minutes * 60
        remainingSeconds += additionalSeconds
        HaispaceLogger.info("Waktu ditambahkan \(minutes) menit. Sisa waktu: \(remainingSeconds)s", category: "session")
    }

    // MARK: - Private: Session Timer

    private func startSessionTimer() {
        sessionTimerTask = Task { [weak self] in
            guard let self else { return }

            // Dengarkan pesan photo (Channel 1: Thumbnail & Channel 2: Full)
            Task {
                for await message in P2PMessageRouter.shared.messageStream(for: .photoPreview) {
                    guard case .photoPreview(let id, let thumbnailData) = message else { continue }
                    await MainActor.run {
                        let thumbnail = PhotoThumbnail(photoId: id, data: thumbnailData, capturedAt: Date(), sortOrder: self.photos.capturedCount)
                        self.photos.receiveThumbnail(thumbnail)
                    }
                }
            }
            
            Task {
                for await message in P2PMessageRouter.shared.messageStream(for: .photoFull) {
                    guard case .photoFull(let id, let fullData) = message else { continue }
                    await MainActor.run {
                        self.photos.upgradeToFullQuality(photoId: id, fullData: fullData)
                        // Kirim ACK kembali ke iPhone dengan checksum dari ukuran data
                        let checksum = String(fullData.count)
                        Task {
                            await P2PMessageRouter.shared.route(.photoAck(photoId: id, checksum: checksum))
                        }
                    }
                }
            }

            while self.remainingSeconds > 0 {
                guard !Task.isCancelled else { return }

                try? await Task.sleep(for: .seconds(1))

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if self.remainingSeconds > 0 {
                        self.remainingSeconds -= 1
                    }
                }
            }

            // Timer habis — transisi ke photo selection
            await MainActor.run {
                guard !Task.isCancelled else { return }
                // Grace period: jika sedang countdown foto terakhir, tunggu selesai
                if self.status == .active {
                    self.proceedToPhotoSelection()
                }
            }
        }
    }

    // MARK: - Helper

    private func calculateTotalAmount() -> Int {
        var total = package_.price
        // TODO: Fase 2 — tambahkan harga add-on yang dipilih
        return total
    }
}
