// SessionFactory.swift
// HaispaceBooths — Core/Domain/Session
//
// Domain Factory untuk membuat HaispaceSession Aggregate Root baru.
//
// PRINSIP (Ref: GPT Architecture Review):
//   Session bukan sekadar dibuat via initializer biasa.
//   Ia harus memenuhi seluruh business invariants sejak detik pertama lahir.
//
// TANGGUNG JAWAB FACTORY:
//   1. Validasi keabsahan Package (durasi > 0, count valid)
//   2. Ekstraksi CapturePolicy dari Package
//   3. Konstruksi SessionIdentity (sessionId UUID, boothId, eventId, versions)
//   4. Konstruksi HaispaceSession Aggregate Root yang siap pakai
//
// WorkflowOrchestrator menerima HaispaceSession yang SUDAH VALID dari Factory ini.
//
// Ref: haispace-platform/adr/ADR-009-session-aggregate-repository.md

import Foundation

// MARK: - SessionFactory

public enum SessionFactory {

    /// Buat HaispaceSession Aggregate Root baru yang valid secara domain.
    ///
    /// - Parameters:
    ///   - guest: Data tamu yang mendaftar
    ///   - package: BoothPackage yang dipilih
    ///   - boothId: Identitas booth (default dari environment)
    ///   - eventId: Identitas event yang sedang berlangsung
    ///   - manifestVersion: Versi manifest aktif
    ///   - packageVersion: Versi package aktif
    /// - Throws: `SessionFactoryError` jika paket atau data tamu tidak memenuhi invariant awal.
    public static func createSession(
        guest: SessionGuest,
        package: BoothPackage,
        boothId: String = "booth-01",
        eventId: String = "event-active",
        manifestVersion: Int = 1,
        packageVersion: Int = 1
    ) throws -> HaispaceSession {

        // Invariant Guard 1: Data tamu tidak boleh kosong
        guard !guest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SessionFactoryError.invalidGuestData("Guest name cannot be empty")
        }

        // Invariant Guard 2: Package duration & count harus valid secara bisnis
        guard package.durationSeconds > 0 else {
            throw SessionFactoryError.invalidPackage("Package duration must be greater than 0 seconds")
        }

        guard package.maxPhotoCount > 0 && package.minPhotoCount > 0 else {
            throw SessionFactoryError.invalidPackage("Package photo limits must be positive")
        }

        guard package.minPhotoCount <= package.maxPhotoCount else {
            throw SessionFactoryError.invalidPackage("Package minPhotoCount cannot exceed maxPhotoCount")
        }

        // 1. Construct Identity
        let identity = SessionIdentity(
            sessionId: UUID().uuidString,
            boothId: boothId,
            eventId: eventId,
            packageId: package.id,
            packageVersion: packageVersion,
            manifestVersion: manifestVersion,
            startedAt: Date(),
            guest: guest
        )

        // 2. Construct CapturePolicy from Package
        let capturePolicy = CapturePolicy.from(package: package)

        // 3. Instantiate Aggregate Root
        let session = HaispaceSession(
            identity: identity,
            capturePolicy: capturePolicy
        )

        HaispaceLogger.info(
            "SessionFactory: HaispaceSession created successfully (\(identity.sessionId)) for guest \(guest.name)",
            category: "session"
        )

        return session
    }
}

// MARK: - SessionFactoryError

public enum SessionFactoryError: Error, Sendable, LocalizedError {
    case invalidGuestData(String)
    case invalidPackage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidGuestData(let msg): return "Data tamu tidak valid: \(msg)"
        case .invalidPackage(let msg): return "Paket foto tidak valid: \(msg)"
        }
    }
}
