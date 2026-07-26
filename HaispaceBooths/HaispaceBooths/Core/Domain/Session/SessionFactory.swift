// SessionFactory.swift
// HaispaceBooths — Core/Domain/Session
//
// Domain Factory untuk membuat HaispaceSession Aggregate Root baru.
//
// PRINSIP (Ref: GPT Architecture Review):
//   Session bukan sekadar dibuat via initializer biasa.
//   Ia harus memenuhi seluruh business invariants sejak detik pertama lahir.
//   SessionFactory adalah satu-satunya tempat yang boleh melakukan:
//     - create()   → Session baru dari tamu dan package
//     - restore()  → Session yang di-recover dari SessionSnapshot (setelah crash)
//     - migrate()  → Session dari snapshot versi lama (schema migration)
//     - clone()    → Duplikasi session (future — untuk testing dan demo)
//
// WorkflowOrchestrator menerima HaispaceSession yang SUDAH VALID dari Factory ini.
// WorkflowOrchestrator TIDAK boleh memanggil HaispaceSession() secara langsung.
//
// Ref: haispace-platform/adr/ADR-009-session-aggregate-repository.md

import Foundation

// MARK: - SessionFactory

public enum SessionFactory {

    // MARK: - create()

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
            "SessionFactory.create: (\(identity.sessionId)) guest: \(guest.name)",
            category: "session"
        )

        return session
    }

    // MARK: - restore()

    /// Pulihkan HaispaceSession dari SessionSnapshot yang tersimpan di disk.
    /// Dipanggil oleh Recovery Engine saat app launch mendeteksi in-progress session.
    ///
    /// - Parameter snapshot: SessionSnapshot yang diload dari SessionRepository
    /// - Parameter package: BoothPackage aktif (diload ulang karena Policy tidak disimpan di snapshot)
    /// - Throws: `SessionFactoryError.incompatibleSnapshot` jika schema tidak kompatibel.
    ///
    /// NOTE: Implementasi lengkap akan ditambahkan pada Phase C (Recovery Engine).
    ///       API ini sudah distabilkan agar tidak breaking change saat Phase C dimulai.
    public static func restoreSession(
        from snapshot: SessionSnapshot,
        package: BoothPackage
    ) throws -> HaispaceSession {
        // Phase C: Implementasi penuh saat Recovery Engine dibangun
        // Saat ini hanya membuat session baru dengan identity dari snapshot
        // sebagai placeholder agar API contract tidak berubah saat Phase C.

        HaispaceLogger.warning(
            "SessionFactory.restore: Stub implementation — Phase C belum diimplementasikan untuk sessionId: \(snapshot.sessionId)",
            category: "session"
        )

        let guest = SessionGuest(
            name: snapshot.guestName,
            phoneNumber: snapshot.guestPhone,
            queueNumber: snapshot.guestQueueNumber
        )

        return try createSession(
            guest: guest,
            package: package,
            boothId: snapshot.boothId,
            eventId: snapshot.eventId,
            manifestVersion: snapshot.manifestVersion,
            packageVersion: snapshot.packageVersion
        )
    }

    // MARK: - migrate()

    /// Migrasi SessionSnapshot dari versi schema lama ke versi terkini.
    /// Dipanggil oleh SessionRepository saat load snapshot dengan snapshotSchemaVersion lama.
    ///
    /// - Parameter snapshot: SessionSnapshot versi lama
    /// - Returns: SessionSnapshot versi terkini yang sudah di-migrate
    ///
    /// NOTE: Implementasi migration logic ditambahkan di sini saat snapshotSchemaVersion naik.
    ///       Saat ini hanya versi 1, jadi tidak ada migration yang diperlukan.
    public static func migrateSnapshot(_ snapshot: SessionSnapshot) -> SessionSnapshot {
        // Delegasi ke SessionSnapshot.migrated() yang sudah ada
        return snapshot.migrated()
    }
}

// MARK: - SessionFactoryError

public enum SessionFactoryError: Error, Sendable, LocalizedError {
    case invalidGuestData(String)
    case invalidPackage(String)
    case incompatibleSnapshot(schemaVersion: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidGuestData(let msg): return "Data tamu tidak valid: \(msg)"
        case .invalidPackage(let msg): return "Paket foto tidak valid: \(msg)"
        case .incompatibleSnapshot(let v, let r): return "Snapshot schema v\(v) tidak kompatibel: \(r)"
        }
    }
}
