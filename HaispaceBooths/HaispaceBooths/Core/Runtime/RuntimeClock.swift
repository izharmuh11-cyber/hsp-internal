// RuntimeClock.swift
// HaispaceBooths — Core/Runtime
//
// Abstraksi waktu untuk seluruh Platform Runtime Haispace.
//
// PRINSIP (Ref: GPT Architecture Review):
//   Runtime hanya mengenal satu sumber waktu: Clock.
//   Tidak ada Date() langsung di dalam Domain atau Runtime.
//   Semua timestamp berasal dari Clock.now().
//
// IMPLEMENTASI:
//   SystemClock   → runtime iPad, menggunakan Date() sistem
//   FixedClock    → unit testing, timestamp deterministik
//   ReplayClock   → future — Phase C Recovery replay
//   ManualClock   → future — debugging & time-travel
//
// KEUNTUNGAN:
//   - Testing Domain menjadi deterministik (tidak tergantung waktu mesin)
//   - Recovery Engine dapat "memutar ulang" sequence events dengan benar
//   - Distributed Sync tidak bergantung pada clock drift antar device
//
// Ref: GPT Architecture Review — RuntimeClock sebelum AppState integration

import Foundation

// MARK: - RuntimeClockProtocol

/// Sumber waktu tunggal untuk seluruh Platform Runtime.
/// Semua komponen yang butuh timestamp mengambil dari sini — bukan dari Date().
public protocol RuntimeClockProtocol: Sendable {
    /// Waktu saat ini menurut clock ini.
    var now: Date { get }

    /// Identifikasi implementasi (untuk logging dan debugging).
    var clockId: String { get }
}

// MARK: - SystemClock

/// Implementasi default: menggunakan system clock iPad.
/// Digunakan di production runtime.
public struct SystemClock: RuntimeClockProtocol {
    public let clockId = "system"
    public var now: Date { Date() }
    public init() {}
}

// MARK: - FixedClock

/// Clock dengan waktu tetap — untuk unit testing.
/// Memastikan semua test yang melibatkan timestamp bersifat deterministik.
///
/// Penggunaan:
/// ```swift
/// let clock = FixedClock(fixedDate: Date(timeIntervalSince1970: 1_700_000_000))
/// let session = SessionFactory.createSession(guest: ..., package: ..., clock: clock)
/// ```
public struct FixedClock: RuntimeClockProtocol {
    public let clockId = "fixed"
    public let fixedDate: Date
    public var now: Date { fixedDate }

    public init(fixedDate: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.fixedDate = fixedDate
    }
}

// MARK: - OffsetClock

/// Clock yang memiliki offset dari system time.
/// Berguna untuk mensimulasikan kondisi "3 jam dari sekarang" dalam testing.
public struct OffsetClock: RuntimeClockProtocol {
    public let clockId = "offset"
    public let offset: TimeInterval
    public var now: Date { Date().addingTimeInterval(offset) }

    public init(offset: TimeInterval) {
        self.offset = offset
    }
}

// MARK: - ReplayClock (Stub — Phase C)

/// Clock yang memutar ulang sequence waktu berdasarkan event log.
/// Digunakan oleh Recovery Engine untuk merekonstruksi state dengan benar.
///
/// NOTE: Implementasi Phase C (Recovery Engine). Saat ini berperilaku seperti SystemClock.
public final class ReplayClock: RuntimeClockProtocol, @unchecked Sendable {
    public let clockId = "replay"
    private var replayDate: Date

    public var now: Date { replayDate }

    public init(startingAt date: Date = Date()) {
        self.replayDate = date
    }

    /// Majukan waktu replay ke timestamp event berikutnya.
    /// Dipanggil oleh Recovery Engine saat memutar ulang event sequence.
    public func advance(to date: Date) {
        replayDate = date
    }
}
