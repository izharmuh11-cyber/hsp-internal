// HaispaceError+Localized.swift
// HaispaceBooths — Core/Error
//
// Pesan error dalam Bahasa Indonesia yang human-readable.
// Semua pesan yang ditampilkan ke tamu/operator HARUS melalui sini.
//
// Aturan: Error yang tampil ke tamu HARUS dalam Bahasa Indonesia.
// Ref: docs/design/41_error_handling.md

import Foundation

extension HaispaceError: LocalizedError {

    /// Pesan utama error — ditampilkan di alert/banner
    var errorDescription: String? {
        switch self {
        // P2P
        case .p2pConnectionFailed(let reason):
            return "Koneksi ke kamera gagal: \(reason.localizedDescription)"
        case .p2pConnectionLost:
            return "Koneksi ke kamera terputus"
        case .p2pMessageSendFailed(let type):
            return "Gagal mengirim pesan '\(type)' ke kamera"
        case .p2pReconnectExhausted(let attempts):
            return "Gagal terhubung kembali setelah \(attempts) percobaan"

        // Kamera
        case .cameraPermissionDenied:
            return "Izin kamera diperlukan untuk menggunakan HaiCamera"
        case .cameraSetupFailed:
            return "Kamera gagal diinisialisasi"
        case .captureSessionInterrupted(let reason):
            return "Sesi kamera terganggu: \(reason)"
        case .photoCaptureFailed:
            return "Gagal mengambil foto"
        case .streamingStartFailed:
            return "Gagal memulai streaming kamera"

        // Transfer
        case .thumbnailCompressionFailed:
            return "Gagal memproses pratinjau foto"
        case .fullQualityTransferFailed(_, let attempt):
            return "Gagal mentransfer foto (percobaan ke-\(attempt))"
        case .photoDecodeFailed:
            return "Gagal memuat foto"

        // CoreData
        case .coreDataSaveFailed(let entity, _):
            return "Gagal menyimpan data '\(entity)'"
        case .coreDataFetchFailed(let entity, _):
            return "Gagal memuat data '\(entity)'"
        case .storageInsufficient(let required, let available):
            let req = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let avail = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Penyimpanan tidak cukup. Dibutuhkan \(req), tersedia \(avail)"

        // Pembayaran
        case .qrisGenerationFailed(let reason):
            return "Gagal membuat kode QRIS: \(reason)"
        case .paymentTimeout:
            return "Pembayaran melebihi batas waktu"

        // Lisensi
        case .licenseExpired(let days):
            return "Lisensi sudah kadaluarsa \(days) hari yang lalu"
        case .licenseInvalid(let reason):
            return "Lisensi tidak valid: \(reason.localizedDescription)"
        case .licenseDeviceLimitReached:
            return "Batas maksimal perangkat tercapai untuk lisensi ini"
        case .licenseHeartbeatFailed:
            return "Verifikasi lisensi ke server gagal"
        case .jailbreakDetected:
            return "Perangkat tidak kompatibel karena alasan keamanan"

        // Cloud / Network
        case .networkUnavailable:
            return "Tidak ada koneksi internet"
        case .uploadFailed(_, let status):
            if let status {
                return "Upload gagal (HTTP \(status))"
            }
            return "Upload gagal"
        case .apiResponseInvalid(let endpoint):
            return "Respons server tidak valid dari '\(endpoint)'"
        case .authTokenExpired:
            return "Sesi login telah kadaluarsa. Silakan login kembali"
        case .authTokenInvalid:
            return "Token autentikasi tidak valid"

        // Filter / Rendering
        case .lutFileNotFound(let name):
            return "File filter '\(name)' tidak ditemukan"
        case .lutFileParseFailed(let name, let reason):
            return "Gagal memuat filter '\(name)': \(reason)"
        case .filterRenderFailed(let name):
            return "Gagal menerapkan filter '\(name)'"
        case .frameCompositeFailed(let id):
            return "Gagal menggabungkan foto dengan bingkai (ID: \(id))"

        // Printer
        case .printerNotFound:
            return "Printer tidak ditemukan di jaringan lokal"
        case .printerJobFailed:
            return "Gagal mencetak foto"

        // System
        case .thermalThrottling(let state):
            return "Kamera melambat karena perangkat terlalu panas (Level: \(state.rawValue))"
        case .unknown(let error):
            return "Terjadi kesalahan: \(error.localizedDescription)"
        }
    }

    /// Saran pemulihan — opsional, ditampilkan di bawah pesan utama
    var recoverySuggestion: String? {
        switch self {
        case .p2pConnectionLost, .p2pConnectionFailed:
            return "Pastikan iPhone dan iPad masih dalam jangkauan WiFi atau Bluetooth"
        case .p2pReconnectExhausted:
            return "Coba restart WiFi dan Bluetooth di kedua perangkat"
        case .cameraPermissionDenied:
            return "Buka Pengaturan → HaiCamera → Izinkan Kamera"
        case .storageInsufficient:
            return "Hapus file lama atau pindahkan foto ke cloud untuk membebaskan ruang"
        case .licenseExpired:
            return "Hubungi admin untuk memperpanjang lisensi"
        case .licenseInvalid:
            return "Hubungi admin untuk verifikasi activation key"
        case .licenseDeviceLimitReached:
            return "Nonaktifkan perangkat lama di Web Dashboard terlebih dahulu"
        case .paymentTimeout:
            return "Minta tamu untuk scan ulang kode QR atau bayar tunai"
        case .qrisGenerationFailed:
            return "Gunakan metode pembayaran tunai sementara"
        case .thermalThrottling:
            return "Istirahatkan kamera beberapa menit dan hindari sinar matahari langsung"
        case .printerNotFound:
            return "Pastikan printer Epson L8050 menyala dan tersambung ke WiFi yang sama"
        case .jailbreakDetected:
            return "Hubungi tim Haispace jika Anda merasa ini adalah kesalahan"
        case .authTokenExpired, .authTokenInvalid:
            return "Login ulang dengan email dan password operator"
        default:
            return nil
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
