// HaispaceSession.swift
// HaispaceBooths — Core/Domain/Session
//
// Session Aggregate Root — fondasi Runtime Haispace.
//
// PRINSIP DDD:
//   - Tidak ada object di luar Aggregate yang boleh mengubah state Session langsung.
//   - Semua mutasi melalui method Session: acceptPayment, addCapture, dll.
//   - Session menghasilkan Domain Events untuk setiap perubahan state penting.
//
// ATURAN (Ref: Platform Principles #11 — Immutable Session):
//   - Package, CapturePolicy, Layout, Theme tidak berubah selama Session aktif.
//   - Manifest updates hanya berlaku untuk Session berikutnya.
//
// THREAD SAFETY:
//   - HaispaceSession adalah Swift Actor — aman dari race condition.
//   - Semua mutasi harus melalui async methods di dalam Actor.
//
// Ref: haispace-platform/architecture/ARP-003-session-lifecycle.md
// Ref: haispace-platform/architecture/ARP-004-runtime-persistence-recovery.md
// Ref: haispace-platform/docs/GLOSSARY.md — Session

import Foundation

// MARK: - SessionIdentity

/// Identitas permanen satu Session — immutable setelah dibuat.
public struct SessionIdentity: Codable, Sendable {
    public let sessionId: String         // UUID
    public let boothId: String           // BoothIdentity
    public let eventId: String           // Event yang sedang berlangsung
    public let packageId: String         // Package yang dipilih tamu
    public let packageVersion: Int       // Versi package saat session dimulai
    public let manifestVersion: Int      // Versi manifest saat session dimulai
    public let startedAt: Date
    public let guest: SessionGuest

    public init(
        sessionId: String = UUID().uuidString,
        boothId: String,
        eventId: String,
        packageId: String,
        packageVersion: Int,
        manifestVersion: Int,
        startedAt: Date = Date(),
        guest: SessionGuest
    ) {
        self.sessionId = sessionId
        self.boothId = boothId
        self.eventId = eventId
        self.packageId = packageId
        self.packageVersion = packageVersion
        self.manifestVersion = manifestVersion
        self.startedAt = startedAt
        self.guest = guest
    }
}

// MARK: - SessionGuest

/// Data tamu yang memulai Session — immutable.
public struct SessionGuest: Codable, Sendable {
    public let name: String
    public let phoneNumber: String?
    public let email: String?
    public let queueNumber: Int

    public init(name: String, phoneNumber: String? = nil, email: String? = nil, queueNumber: Int = 1) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.queueNumber = queueNumber
    }

    public var displayName: String { name }

    // MARK: - Bridge from GuestInfo (temporary during migration)
    public static func from(_ info: GuestInfo) -> SessionGuest {
        SessionGuest(
            name: info.name,
            phoneNumber: info.phoneNumber,
            email: nil,
            queueNumber: info.queueNumber
        )
    }
}

// MARK: - SessionLifecycleStatus

/// Status operasional Session — derived dari WorkflowStage, bukan state machine sendiri.
/// Sesuai keputusan GPT (ARP-003): WorkflowStage adalah authoritative, ini hanya representasi.
public enum SessionLifecycleStatus: Codable, Sendable, Equatable {
    case active         // Session sedang berjalan normal
    case paused         // Operator pause
    case recovering     // Sedang dalam proses recovery setelah crash
    case completed      // Session berhasil selesai
    case aborted        // Dibatalkan — tidak ada transaksi finansial
    case abandoned      // Tamu pergi — ada transaksi (perlu tindakan operator)
}

// MARK: - SessionDeliveryState

/// State pengiriman dalam Session — persisted ke DeliveryRepository.
public struct SessionDeliveryState: Codable, Sendable {
    public var queuedItems: [DeliveryQueueReference] = []
    public var completedItems: [String] = []     // DeliveryQueueItem IDs
    public var failedItems: [String] = []

    public var isAllDelivered: Bool {
        !queuedItems.isEmpty && queuedItems.allSatisfy { completedItems.contains($0.itemId) }
    }
}

/// Referensi ringan ke DeliveryQueue item — tidak menyimpan seluruh payload.
public struct DeliveryQueueReference: Codable, Sendable {
    public let itemId: String
    public let channel: String   // "qr", "whatsapp", "airdrop", "print", "audit"
    public let priority: Int
    public let enqueuedAt: Date
}

// MARK: - HaispaceSession (Aggregate Root)

/// Session Aggregate Root.
///
/// **Aturan DDD:**
/// "Workflow knows what happens next. Aggregate decides whether it is allowed."
///
/// Tidak ada object di luar Aggregate yang boleh mengubah state Session langsung.
/// Semua mutasi melalui method Session: acceptPayment, addCapture, dll.
///
/// **Tentang Swift Actor:**
/// Actor adalah detail implementasi concurrency Swift, bukan bagian dari domain.
/// Domain = HaispaceSession (konsep). Concurrency = actor (mekanisme).
/// Jika Platform Core berjalan di server atau backend, konsep Session tetap sama.
///
/// Internal state bersifat private — consumer membaca melalui computed properties.
public actor HaispaceSession {

    // MARK: - Immutable Identity (locked on creation)
    public let identity: SessionIdentity
    public let capturePolicy: CapturePolicy

    // MARK: - Mutable Domain State
    private(set) var lifecycleStatus: SessionLifecycleStatus = .active
    private(set) var currentStage: WorkflowStage = .packageSelection
    private(set) var captures: CaptureCollection = CaptureCollection()
    private(set) var paymentCommitment: PaymentCommitment? = nil
    private(set) var deliveryState: SessionDeliveryState = SessionDeliveryState()
    private(set) var outputReference: String? = nil  // path ke final composite
    private(set) var remainingSeconds: Int
    private(set) var completedAt: Date? = nil
    private(set) var abortedAt: Date? = nil
    private(set) var abortReason: String? = nil

    // MARK: - Domain Event Collector
    // Events dikumpulkan dan di-flush ke Publisher setelah setiap mutasi.
    private var pendingEvents: [SessionDomainEvent] = []

    // MARK: - Init

    public init(identity: SessionIdentity, capturePolicy: CapturePolicy) {
        self.identity = identity
        self.capturePolicy = capturePolicy
        self.remainingSeconds = capturePolicy.durationSeconds
    }

    // MARK: - Business Invariant Queries
    // Ini adalah satu-satunya tempat business rules diperiksa.
    // WorkflowOrchestrator TIDAK boleh mengandung logika ini.

    public var canProceedToPayment: Bool {
        captures.selectedCount >= capturePolicy.minSelectionCount
    }

    public var canBeginDelivery: Bool {
        isFinanciallyCommitted && outputReference != nil
    }

    public var canComplete: Bool {
        isFinanciallyCommitted && deliveryState.isAllDelivered
    }

    public var canOperatorAbort: Bool {
        // Operator boleh membatalkan HANYA jika belum ada transaksi finansial
        // Setelah Accepted, operator harus melewati flow khusus (refund, void)
        !isFinanciallyCommitted
    }

    public var canRetakePhoto: Bool {
        capturePolicy.allowRetake && captures.capturedCount < capturePolicy.maxCount
    }

    public var isAtCaptureLimit: Bool {
        captures.capturedCount >= capturePolicy.maxCount
    }

    // MARK: - Mutations (Workflow commands)
    // Session memvalidasi setiap request berdasarkan business invariants.

    /// Tamu mulai ambil foto — transisi ke capturing stage.
    public func beginCapturing() {
        guard currentStage == .packageSelection || currentStage == .templateSelection else { return }
        currentStage = .capturing
        emit(.capturingBegan(sessionId: sessionId))
    }

    /// Foto baru diterima dari HaiCamera — Session memvalidasi batas maksimal.
    /// - Throws: SessionError.captureAtLimit jika sudah mencapai batas package.
    public func addCapture(_ record: CaptureRecord) throws {
        guard !isAtCaptureLimit else {
            throw SessionError.captureAtLimit(max: capturePolicy.maxCount)
        }
        captures.append(record)
        emit(.capturePersisted(sessionId: sessionId, captureId: record.id, sortOrder: record.sortOrder))
    }

    /// Full quality foto tiba (background transfer selesai).
    public func upgradeCapture(id: String, filePath: String) {
        captures.upgradeToFullQuality(id: id, filePath: filePath)
        emit(.captureUpgraded(sessionId: sessionId, captureId: id))
    }

    /// Tamu selesai mengambil foto — transisi ke photo selection.
    public func proceedToPhotoSelection() {
        currentStage = .editingPreview
        emit(.photoSelectionBegan(sessionId: sessionId, totalCaptures: captures.capturedCount))
    }

    /// Tamu toggle pilihan foto — Session menjaga business rule (min/max).
    public func selectCapture(id: String) throws {
        if captures.isSelected(id) {
            captures.removeFromSelection(id)
        } else {
            guard captures.selectedCount < capturePolicy.maxSelectionCount else {
                throw SessionError.selectionAtLimit(max: capturePolicy.maxSelectionCount)
            }
            captures.addToSelection(id)
        }
        emit(.captureSelectionChanged(sessionId: sessionId, selectedCount: captures.selectedCount))
    }

    /// Tamu memilih frame overlay.
    public func selectFrame(frameId: String?) {
        captures.setFrame(frameId)
    }

    /// Tamu memilih filter.
    public func selectFilter(filterId: String?) {
        captures.setFilter(filterId)
    }

    /// Hasil komposit selesai di-render.
    public func finishProcessing(outputRef: String) {
        outputReference = outputRef
        currentStage = .exporting
        emit(.processingCompleted(sessionId: sessionId, outputReference: outputRef))
    }

    /// Booth memulai proses pembayaran.
    public func requestPayment(method: PaymentCommitmentMethod) {
        paymentCommitment = .pending(method: method, requestedAt: Date())
        currentStage = .paymentRequested
        emit(.paymentRequested(sessionId: sessionId, method: method))
    }

    /// Booth menerima konfirmasi pembayaran lokal — point of no return.
    /// - Throws: SessionError.invalidTransition jika tidak dalam state pending.
    public func acceptPayment(localTransactionId: String, amount: Int, method: PaymentCommitmentMethod) throws {
        guard case .pending = paymentCommitment else {
            throw SessionError.invalidTransition("acceptPayment requires pending state")
        }
        paymentCommitment = .accepted(
            method: method,
            localTransactionId: localTransactionId,
            amount: amount,
            acceptedAt: Date()
        )
        currentStage = .paymentConfirmed
        emit(.paymentAccepted(
            sessionId: sessionId,
            localTransactionId: localTransactionId,
            amount: amount,
            method: method
        ))
    }

    /// Pembayaran ditolak — bukan Abort Session.
    /// - Throws: SessionError.invalidTransition jika sudah Accepted (point-of-no-return).
    public func rejectPayment(reason: PaymentRejectionReason) throws {
        switch paymentCommitment {
        case .accepted, .verified:
            throw SessionError.invalidTransition("Cannot reject payment after acceptance — past point of no return")
        default:
            paymentCommitment = .rejected(method: paymentCommitment?.method ?? .qris, reason: reason, rejectedAt: Date())
            emit(.paymentFailed(sessionId: sessionId, reason: reason.rawValue))
        }
    }

    /// Cloud mengkonfirmasi pembayaran (async — tidak memblokir Workflow).
    public func verifyPayment(serverId: String) throws {
        guard case .accepted(let method, let localId, let amount, _) = paymentCommitment else {
            throw SessionError.invalidTransition("verifyPayment requires accepted state")
        }
        paymentCommitment = .verified(
            method: method,
            localTransactionId: localId,
            serverId: serverId,
            amount: amount,
            verifiedAt: Date()
        )
        emit(.paymentVerified(sessionId: sessionId, serverId: serverId))
    }

    /// Foto siap dikirim ke tamu — Session memvalidasi bahwa payment sudah Accepted.
    /// - Throws: SessionError.invalidTransition jika belum ada PaymentCommitment.accepted.
    public func queueDelivery(item: DeliveryQueueReference) throws {
        guard canBeginDelivery else {
            throw SessionError.invalidTransition("Cannot queue delivery without accepted payment and output reference")
        }
        deliveryState.queuedItems.append(item)
        currentStage = .deliveryDispatch
        emit(.deliveryQueued(sessionId: sessionId, channel: item.channel, priority: item.priority))
    }

    /// Delivery item berhasil terkirim.
    public func markDeliveryCompleted(itemId: String) {
        deliveryState.completedItems.append(itemId)
        if deliveryState.isAllDelivered {
            emit(.allDeliveryCompleted(sessionId: sessionId))
        }
    }

    /// Delivery item gagal.
    public func markDeliveryFailed(itemId: String) {
        deliveryState.failedItems.append(itemId)
        emit(.deliveryFailed(sessionId: sessionId, itemId: itemId))
    }

    /// Session selesai dengan sukses — Session memvalidasi invariant.
    public func complete() throws {
        guard canComplete else {
            throw SessionError.invalidTransition("Session cannot complete: payment not committed or delivery not finished")
        }
        lifecycleStatus = .completed
        currentStage = .sessionCompleted
        completedAt = Date()
        emit(.sessionCompleted(sessionId: sessionId, completedAt: completedAt!))
    }

    /// Operator membatalkan Session — Session memvalidasi apakah cancel diizinkan.
    public func abort(reason: String, byOperatorId: String) throws {
        guard canOperatorAbort else {
            throw SessionError.invalidTransition("Cannot abort session with accepted payment — use void/refund flow instead")
        }
        lifecycleStatus = .aborted
        currentStage = .recoveryMode
        abortedAt = Date()
        abortReason = reason
        emit(.sessionAborted(sessionId: sessionId, reason: reason, byOperatorId: byOperatorId))
    }

    /// Force-abandon — digunakan saat tamu pergi setelah payment (tidak bisa di-abort).
    public func abandon(reason: String) {
        lifecycleStatus = .abandoned
        abortedAt = Date()
        abortReason = reason
        emit(.sessionAborted(sessionId: sessionId, reason: reason, byOperatorId: "system"))
    }

    /// Operator pause Session.
    public func pause() {
        lifecycleStatus = .paused
        emit(.sessionPaused(sessionId: sessionId))
    }

    /// Operator resume Session.
    public func resume() {
        lifecycleStatus = .active
        emit(.sessionResumed(sessionId: sessionId))
    }

    /// Session sedang di-recover setelah crash.
    public func markAsRecovering() {
        lifecycleStatus = .recovering
        emit(.sessionRecovering(sessionId: sessionId))
    }

    // MARK: - Timer

    public func decrementTimer() {
        guard lifecycleStatus == .active && remainingSeconds > 0 else { return }
        remainingSeconds -= 1
    }

    // MARK: - Snapshot (untuk persistence)

    /// Buat snapshot stabil untuk persistence.
    /// Snapshot adalah kontrak penyimpanan — tidak tergantung implementasi internal.
    public func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            snapshotSchemaVersion: 1,
            sessionId: identity.sessionId,
            boothId: identity.boothId,
            eventId: identity.eventId,
            packageId: identity.packageId,
            packageVersion: identity.packageVersion,
            manifestVersion: identity.manifestVersion,
            startedAt: identity.startedAt,
            guestName: identity.guest.name,
            guestPhone: identity.guest.phoneNumber,
            guestQueueNumber: identity.guest.queueNumber,
            workflowStageId: currentStage.rawValue,
            lifecycleStatus: lifecycleStatus.codableRepresentation,
            captureIds: captures.records.map { $0.id },
            captureFilePaths: Dictionary(
                uniqueKeysWithValues: captures.records.map { ($0.id, $0.filePath) }
            ),
            selectedCaptureIds: Array(captures.selectedIds),
            selectedFrameId: captures.selectedFrameId,
            selectedFilterId: captures.selectedFilterId,
            paymentCommitment: paymentCommitment,
            deliveryState: deliveryState,
            outputReference: outputReference,
            remainingSeconds: remainingSeconds,
            completedAt: completedAt,
            abortedAt: abortedAt,
            abortReason: abortReason,
            snapshotAt: Date()
        )
    }

    // MARK: - Pending Events

    /// Ambil dan kosongkan pending events — dipanggil oleh Publisher setelah flush.
    public func flushEvents() -> [SessionDomainEvent] {
        let events = pendingEvents
        pendingEvents.removeAll()
        return events
    }

    private func emit(_ event: SessionDomainEvent) {
        pendingEvents.append(event)
    }
}

// MARK: - SessionError

public enum SessionError: Error, Sendable {
    case invalidTransition(String)
    case captureNotFound(String)
    case paymentAlreadyCommitted
    case captureAtLimit(max: Int)         // Mencapai batas maxCount dari CapturePolicy
    case selectionAtLimit(max: Int)       // Mencapai batas maxSelectionCount dari CapturePolicy
    case deliveryNotAllowed(String)       // Payment belum Accepted
    case completionNotAllowed(String)     // Delivery belum selesai
}

// MARK: - SessionLifecycleStatus + Codable Helper

extension SessionLifecycleStatus {
    var codableRepresentation: String {
        switch self {
        case .active: return "active"
        case .paused: return "paused"
        case .recovering: return "recovering"
        case .completed: return "completed"
        case .aborted: return "aborted"
        case .abandoned: return "abandoned"
        }
    }

    static func from(string: String) -> SessionLifecycleStatus {
        switch string {
        case "active": return .active
        case "paused": return .paused
        case "recovering": return .recovering
        case "completed": return .completed
        case "aborted": return .aborted
        case "abandoned": return .abandoned
        default: return .recovering // safe default
        }
    }
}
