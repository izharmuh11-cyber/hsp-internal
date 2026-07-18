// Logger.swift
// HaispaceBooths — Core/Logging
//
// Satu-satunya cara logging yang diizinkan di seluruh codebase.
// Jangan gunakan print() untuk error — tidak masuk ke crash report.
//
// Ref: docs/design/41_error_handling.md — Logging Pattern

import Foundation
import OSLog

// MARK: - Log Level

enum LogLevel {
    case debug
    case info
    case warning
    case error
    case critical
}

// MARK: - Logger

/// Wrapper di atas OSLog yang terintegrasi dengan Instruments dan crash reporting.
/// Gunakan ini untuk semua logging, bukan `print()`.
struct HaispaceLogger {

    // OSLog subsystem berdasarkan Bundle ID target
    private static let boothSubsystem = "id.haispaceproject.booth"

    // MARK: Error Logging

    /// Log error ke OSLog dan local log file.
    /// Dipanggil otomatis oleh ErrorHandler — tidak perlu dipanggil langsung.
    static func error(
        _ error: HaispaceError,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let message = "[\(filename):\(line) \(function)] \(error.errorDescription ?? error.localizedDescription)"

        let logger = os.Logger(subsystem: boothSubsystem, category: "error")
        logger.error("\(message, privacy: .public)")

        // Simpan ke local log file untuk crash intelligence
        LocalLogWriter.write(level: .error, message: message)
    }

    /// Log error umum (non-HaispaceError) — wrap ke unknown secara otomatis
    static func error(
        _ error: Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let wrapped = HaispaceError.unknown(underlying: error)
        self.error(wrapped, file: file, function: function, line: line)
    }

    // MARK: Info Logging

    static func info(
        _ message: String,
        category: String = "general",
        file: String = #file,
        function: String = #function
    ) {
        let logger = os.Logger(subsystem: boothSubsystem, category: category)
        logger.info("\(message, privacy: .public)")
        
        LocalLogWriter.write(level: .info, message: message)
    }

    // MARK: Debug Logging (hanya di DEBUG build)

    static func debug(
        _ message: String,
        category: String = "debug",
        file: String = #file,
        function: String = #function
    ) {
        #if DEBUG
        let logger = os.Logger(subsystem: boothSubsystem, category: category)
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    // MARK: Warning Logging

    static func warning(
        _ message: String,
        category: String = "warning",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let fullMessage = "[\(filename):\(line)] \(message)"

        let logger = os.Logger(subsystem: boothSubsystem, category: category)
        logger.warning("\(fullMessage, privacy: .public)")

        LocalLogWriter.write(level: .warning, message: fullMessage)
    }

    // MARK: Critical Logging

    static func critical(
        _ message: String,
        category: String = "critical",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let fullMessage = "[\(filename):\(line) \(function)] CRITICAL: \(message)"

        let logger = os.Logger(subsystem: boothSubsystem, category: category)
        logger.critical("\(fullMessage, privacy: .public)")

        LocalLogWriter.write(level: .critical, message: fullMessage)
    }
}

// MARK: - Local Log Writer

/// Menulis log ke file lokal untuk crash intelligence dan debugging offline.
/// File disimpan di app's Documents directory agar bisa diakses via Xcode Device Manager.
struct LocalLogWriter {

    private static let maxLogFileSizeBytes: Int64 = 5 * 1024 * 1024 // 5MB max

    /// Tulis satu baris log ke file
    static func write(level: LogLevel, message: String) {
        Task.detached(priority: .background) {
            guard let logURL = logFileURL() else { return }

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let levelTag = levelString(level)
            let logLine = "[\(timestamp)] [\(levelTag)] \(message)\n"

            guard let data = logLine.data(using: .utf8) else { return }

            do {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    // Rotasi jika file terlalu besar
                    let attr = try FileManager.default.attributesOfItem(atPath: logURL.path)
                    let size = attr[.size] as? Int64 ?? 0
                    if size > maxLogFileSizeBytes {
                        rotateLog(at: logURL)
                    }
                    // Append ke file yang ada
                    let handle = try FileHandle(forWritingTo: logURL)
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try handle.close()
                } else {
                    // Buat file baru
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                // Tidak bisa log error dari logger itu sendiri — silent
            }
        }
    }

    /// URL file log aktif
    static func logFileURL() -> URL? {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docsDir.appendingPathComponent("haispace_booth.log")
    }

    /// Ambil isi log sebagai string (untuk dikirim ke support/debugging)
    static func readLogContent() -> String {
        guard let url = logFileURL(),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Log file tidak ditemukan atau kosong."
        }
        return content
    }

    /// Hapus semua log (dipanggil operator dari Mission Control)
    static func clearLog() {
        guard let url = logFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Private Helpers

    private static func levelString(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRIT"
        }
    }

    private static func rotateLog(at url: URL) {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("haispace_booth.log.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}

// MARK: - GitHub Auto Log Uploader

struct GitHubLogUploader {
    // PENTING: Token TIDAK boleh di-hardcode di source code.
    // GitHub Security akan otomatis merevoke token yang terekspos di public repo.
    // Token harus diisi manual oleh operator lewat UI LogViewer (disimpan di UserDefaults).
    private static let patKey = "github_pat"
    
    /// Ambil token dari UserDefaults. Return nil jika kosong atau format tidak valid.
    static func resolvedToken() -> String? {
        let token = UserDefaults.standard.string(forKey: patKey) ?? ""
        let isValid = token.hasPrefix("ghp_") || token.hasPrefix("github_pat_")
        return isValid ? token : nil
    }
    
    static func uploadLatestLog(eventName: String = "auto_event") {
        guard let token = resolvedToken() else {
            // Tidak log warning setiap kali — operator belum input token
            return
        }
        
        let logContent = LocalLogWriter.readLogContent()
        guard !logContent.isEmpty && logContent != "Log file tidak ditemukan atau kosong." else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        
        // Clean event name for safe filename
        let cleanEvent = eventName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            
        let filename = "ipad-log-\(timestamp)-\(cleanEvent).txt"
        
        guard let url = URL(string: "https://api.github.com/repos/izharmuh11-cyber/hsp-internal/contents/logs/\(filename)") else {
            HaispaceLogger.warning("Gagal membuat URL untuk upload log: \(filename)", category: "logging")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let base64Content = Data(logContent.utf8).base64EncodedString()
        let body: [String: Any] = [
            "message": "Auto upload log from iPad [\(cleanEvent)] at \(timestamp)",
            "content": base64Content,
            "branch": "main"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                HaispaceLogger.warning("Auto upload log gagal: \(error.localizedDescription)", category: "logging")
            } else if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    HaispaceLogger.info("Auto upload log sukses! File: \(filename)", category: "logging")
                } else {
                    HaispaceLogger.warning("Auto upload log gagal dengan status: \(httpResponse.statusCode)", category: "logging")
                }
            }
        }.resume()
    }
}


