// HaispaceError+Localized.swift
// HaispaceBooths — Core/Error
//
// Pesan error dalam Bahasa Indonesia yang menenangkan, jelas, dan actionable.
// Semua pesan yang ditampilkan ke tamu/operator HARUS melalui sini.
//
// PRINSIP PENULISAN PESAN ERROR (Apple HIG + Kiosk UX):
// - Tamu TIDAK boleh melihat pesan teknis ("HTTP 500", "nil", stack trace)
// - Gunakan bahasa yang menenangkan: "sedang menyiapkan", "belum berhasil"
// - Selalu beri tahu apa yang akan terjadi selanjutnya
// - Operator boleh mendapat detail teknis via `operatorNote`
//
// Ref: docs/design/41_error_handling.md
// Ref: docs/design/ADR-003_platform_reliability.md

import Foundation

extension HaispaceError: LocalizedError {

    // MARK: - errorDescription (Pesan untuk Tamu — Bahasa Menenangkan)

    /// Pesan utama — ditampilkan langsung ke tamu di layar
    var errorDescription: String? {
        switch self {

        // ── P2P / Kamera Remote ──────────────────────────────────────────────
        case .p2pConnectionFailed:
            return "Kamera sedang menyambungkan diri. Mohon tunggu sebentar."
        case .p2pConnectionLost:
            return "Koneksi ke kamera sempat terputus. Sistem sedang menyambungkan kembali."
        case .p2pMessageSendFailed:
            return "Kamera belum merespons. Sistem akan mencoba lagi secara otomatis."
        case .p2pReconnectExhausted:
            return "Kamera tidak dapat terhubung saat ini. Mohon panggil operator untuk bantuan."

        // ── Kamera ──────────────────────────────────────────────────────────
        case .cameraPermissionDenied:
            return "Akses kamera diperlukan untuk melanjutkan. Mohon hubungi operator."
        case .cameraSetupFailed:
            return "Kamera sedang menyiapkan diri. Mohon tunggu sebentar."
        case .captureSessionInterrupted:
            return "Sesi foto terganggu sejenak. Sistem sedang memulihkan kamera."
        case .photoCaptureFailed:
            return "Foto belum berhasil diambil. Sistem akan mencoba lagi secara otomatis."
        case .streamingStartFailed:
            return "Tampilan kamera sedang dimuat. Mohon tunggu sebentar."

        // ── Transfer Foto ────────────────────────────────────────────────────
        case .thumbnailCompressionFailed:
            return "Pratinjau foto sedang diproses. Mohon tunggu sebentar."
        case .fullQualityTransferFailed(_, let attempt):
            if attempt <= 2 {
                return "Foto sedang dikirim ke perangkat ini. Mohon tunggu sebentar."
            } else {
                return "Pengiriman foto membutuhkan waktu lebih lama dari biasanya. Operator sudah diberitahu."
            }
        case .photoDecodeFailed:
            return "Foto sedang dimuat. Mohon tunggu sebentar."

        // ── Penyimpanan ──────────────────────────────────────────────────────
        case .coreDataSaveFailed:
            return "Data sesi sedang disimpan. Mohon tunggu sebentar."
        case .coreDataFetchFailed:
            return "Memuat data sesi. Mohon tunggu sebentar."
        case .storageInsufficient:
            return "Ruang penyimpanan penuh. Mohon hubungi operator untuk bantuan."

        // ── Pembayaran ───────────────────────────────────────────────────────
        case .qrisGenerationFailed:
            return "Kode pembayaran sedang disiapkan. Mohon tunggu sebentar."
        case .paymentTimeout:
            return "Pembayaran belum kami terima. Jika sudah membayar, sistem akan memperbarui secara otomatis."

        // ── Lisensi (Operator-only, tidak tampil ke tamu) ────────────────────
        case .licenseExpired(let days):
            return "Layanan tidak tersedia saat ini. Mohon hubungi operator. (Kode: LIC-EXP-\(days))"
        case .licenseInvalid:
            return "Layanan tidak tersedia saat ini. Mohon hubungi operator."
        case .licenseDeviceLimitReached:
            return "Layanan tidak tersedia saat ini. Mohon hubungi operator."
        case .licenseHeartbeatFailed:
            return "Verifikasi lisensi sedang diproses. Koneksi internet diperlukan."
        case .jailbreakDetected:
            return "Perangkat tidak dapat menjalankan layanan ini. Hubungi tim Haispace."

        // ── Jaringan & Cloud ─────────────────────────────────────────────────
        case .networkUnavailable:
            return "Koneksi internet sedang tidak tersedia. Fitur offline tetap berjalan normal."
        case .uploadFailed:
            return "Pengiriman foto digital sedang dalam antrean dan akan dikirim saat koneksi kembali."
        case .apiResponseInvalid:
            return "Server sedang sibuk. Sistem akan mencoba lagi secara otomatis."
        case .authTokenExpired:
            return "Sesi operator telah berakhir. Silakan login kembali."
        case .authTokenInvalid:
            return "Akses tidak dikenali. Silakan login ulang."

        // ── Filter & Rendering ───────────────────────────────────────────────
        case .lutFileNotFound(let name):
            return "Filter '\(name)' tidak tersedia saat ini."
        case .lutFileParseFailed(let name, _):
            return "Filter '\(name)' sedang dimuat. Mohon tunggu sebentar."
        case .filterRenderFailed:
            return "Penerapan filter membutuhkan waktu lebih lama. Mohon tunggu sebentar."
        case .frameCompositeFailed:
            return "Penggabungan bingkai foto sedang diproses. Mohon tunggu sebentar."

        // ── Printer ──────────────────────────────────────────────────────────
        case .printerNotFound:
            return "Printer sedang menyiapkan diri. Mohon tunggu sebentar."
        case .printerJobFailed:
            return "Printer sedang menyiapkan kembali. Mohon tunggu sebentar."

        // ── Sistem ───────────────────────────────────────────────────────────
        case .thermalThrottling:
            return "Perangkat sedang mendinginkan diri sejenak. Layanan tetap berjalan."
        case .unknown:
            return "Terjadi kendala kecil. Sistem sedang memulihkan diri secara otomatis."
        }
    }

    // MARK: - recoverySuggestion (Saran Tindakan — Untuk Tamu)

    /// Langkah lanjutan yang bisa dilakukan tamu — tampil di bawah pesan utama
    var recoverySuggestion: String? {
        switch self {
        case .p2pConnectionLost, .p2pConnectionFailed, .p2pReconnectExhausted:
            return "Mohon panggil operator jika layar tidak kembali normal dalam 30 detik."
        case .paymentTimeout:
            return "Tidak perlu panik — foto Anda aman. Silakan scan ulang kode QR untuk melanjutkan."
        case .qrisGenerationFailed:
            return "Silakan hubungi operator untuk pilihan pembayaran lainnya."
        case .storageInsufficient:
            return "Silakan hubungi operator. Foto Anda tidak akan hilang."
        case .printerNotFound, .printerJobFailed:
            return "Silakan tunggu — operator sedang diberitahu secara otomatis."
        case .networkUnavailable:
            return "Foto cetak dan softcopy akan dikirim begitu koneksi kembali tersedia."
        case .thermalThrottling:
            return "Layanan akan kembali normal dalam beberapa menit."
        case .licenseExpired, .licenseInvalid, .licenseDeviceLimitReached:
            return "Hubungi tim Haispace di nomor yang tertera di booth."
        case .authTokenExpired, .authTokenInvalid:
            return "Gunakan email dan password operator untuk login kembali."
        default:
            return nil
        }
    }

    // MARK: - operatorNote (Detail Teknis — Hanya untuk Operator & MissionControl)

    /// Detail teknis error — TIDAK boleh ditampilkan ke tamu
    /// Dipakai oleh MissionControlView dan log system
    var operatorNote: String {
        switch self {
        case .p2pConnectionFailed(let reason):
            return "[P2P] Connection failed: \(reason.localizedDescription)"
        case .p2pConnectionLost:
            return "[P2P] Connection lost unexpectedly"
        case .p2pMessageSendFailed(let type):
            return "[P2P] Failed to send message type: '\(type)'"
        case .p2pReconnectExhausted(let attempts):
            return "[P2P] Reconnect exhausted after \(attempts) attempts"
        case .cameraPermissionDenied:
            return "[CAM] Permission denied — check Settings > HaiCamera > Camera"
        case .cameraSetupFailed:
            return "[CAM] AVCaptureSession setup failed"
        case .captureSessionInterrupted(let reason):
            return "[CAM] Session interrupted: \(reason)"
        case .photoCaptureFailed:
            return "[CAM] AVCapturePhotoOutput capture failed"
        case .streamingStartFailed:
            return "[CAM] Streaming start failed"
        case .thumbnailCompressionFailed:
            return "[XFER] JPEG thumbnail compression failed"
        case .fullQualityTransferFailed(let id, let attempt):
            return "[XFER] Full quality transfer failed for photoId=\(id) attempt=\(attempt)"
        case .photoDecodeFailed:
            return "[XFER] Photo decode failed"
        case .coreDataSaveFailed(let entity, let error):
            return "[DB] CoreData save failed for entity='\(entity)': \(error.localizedDescription)"
        case .coreDataFetchFailed(let entity, let error):
            return "[DB] CoreData fetch failed for entity='\(entity)': \(error.localizedDescription)"
        case .storageInsufficient(let required, let available):
            let req = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let avail = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "[STORAGE] Insufficient: required=\(req) available=\(avail)"
        case .qrisGenerationFailed(let reason):
            return "[PAY] QRIS generation failed: \(reason)"
        case .paymentTimeout:
            return "[PAY] Payment polling timeout"
        case .licenseExpired(let days):
            return "[LIC] License expired \(days) days ago"
        case .licenseInvalid(let reason):
            return "[LIC] Invalid: \(reason.localizedDescription)"
        case .licenseDeviceLimitReached:
            return "[LIC] Device limit reached"
        case .licenseHeartbeatFailed:
            return "[LIC] Heartbeat to server failed"
        case .jailbreakDetected:
            return "[SEC] Jailbreak detected"
        case .networkUnavailable:
            return "[NET] NWPathMonitor: no connectivity"
        case .uploadFailed(let path, let status):
            return "[NET] Upload failed path='\(path)' status=\(status.map { "\($0)" } ?? "unknown")"
        case .apiResponseInvalid(let endpoint):
            return "[NET] Invalid API response from '\(endpoint)'"
        case .authTokenExpired:
            return "[AUTH] JWT token expired"
        case .authTokenInvalid:
            return "[AUTH] JWT token invalid"
        case .lutFileNotFound(let name):
            return "[RENDER] LUT file not found: '\(name)'"
        case .lutFileParseFailed(let name, let reason):
            return "[RENDER] LUT parse failed: '\(name)' — \(reason)"
        case .filterRenderFailed(let name):
            return "[RENDER] Filter render failed: '\(name)'"
        case .frameCompositeFailed(let id):
            return "[RENDER] Frame composite failed for frameId=\(id)"
        case .printerNotFound:
            return "[PRINT] Printer not found on local network"
        case .printerJobFailed:
            return "[PRINT] Print job failed"
        case .thermalThrottling(let state):
            return "[SYS] Thermal throttling: level=\(state.rawValue)"
        case .unknown(let error):
            return "[SYS] Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - P2PFailReason Localized

extension P2PFailReason {
    var localizedDescription: String {
        switch self {
        case .bluetoothUnavailable: return "Bluetooth tidak aktif"
        case .wifiUnavailable: return "WiFi tidak aktif"
        case .peerNotFound: return "Perangkat tidak ditemukan"
        case .authenticationFailed: return "Autentikasi gagal"
        case .timeout: return "Waktu koneksi habis"
        }
    }
}

// MARK: - LicenseInvalidReason Localized

extension LicenseInvalidReason {
    var localizedDescription: String {
        switch self {
        case .keyNotFound: return "Key tidak terdaftar"
        case .keyRevoked: return "Key telah dicabut oleh admin"
        case .deviceNotBound: return "Perangkat ini tidak terdaftar untuk key ini"
        case .serverUnreachable: return "Server tidak dapat dijangkau"
        case .checksumMismatch: return "Integritas data tidak valid"
        }
    }
}
