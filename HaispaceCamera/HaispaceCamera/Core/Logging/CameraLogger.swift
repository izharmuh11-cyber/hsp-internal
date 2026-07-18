// CameraLogger.swift
// HaispaceCamera — Core/Logging
//
// Logging wrapper untuk HaispaceCamera target.
// Menggunakan subsystem berbeda dari HaiBooth untuk filtering mudah di Instruments.
//
// Ref: docs/design/41_error_handling.md — Logging Pattern

import Foundation
import OSLog

// MARK: - HaispaceLogger (Camera Target)
// Mirror dari HaispaceBooths/Core/Logging/Logger.swift dengan subsystem berbeda

struct HaispaceLogger {
    private static let cameraSubsystem = "id.haispaceproject.camera"

    static func error(
        _ message: String,
        category: String = "error",
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let fullMessage = "[\(filename):\(line) \(function)] \(message)"
        let logger = os.Logger(subsystem: cameraSubsystem, category: category)
        logger.error("\(fullMessage, privacy: .public)")
        LocalLogWriter.write(level: .error, message: fullMessage, subsystem: "camera")
    }

    static func info(
        _ message: String,
        category: String = "general"
    ) {
        let logger = os.Logger(subsystem: cameraSubsystem, category: category)
        logger.info("\(message, privacy: .public)")
        LocalLogWriter.write(level: .info, message: message, subsystem: "camera")
    }

    static func debug(
        _ message: String,
        category: String = "debug"
    ) {
        #if DEBUG
        let logger = os.Logger(subsystem: cameraSubsystem, category: category)
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func warning(
        _ message: String,
        category: String = "warning",
        file: String = #file,
        line: Int = #line
    ) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let fullMessage = "[\(filename):\(line)] \(message)"
        let logger = os.Logger(subsystem: cameraSubsystem, category: category)
        logger.warning("\(fullMessage, privacy: .public)")
        LocalLogWriter.write(level: .warning, message: fullMessage, subsystem: "camera")
    }

    static func critical(
        _ message: String,
        category: String = "critical",
        file: String = #file,
        line: Int = #line
    ) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let fullMessage = "[\(filename):\(line)] CRITICAL: \(message)"
        let logger = os.Logger(subsystem: cameraSubsystem, category: category)
        logger.critical("\(fullMessage, privacy: .public)")
        LocalLogWriter.write(level: .critical, message: fullMessage, subsystem: "camera")
    }
}

// MARK: - Log Level (Mirror)

enum LogLevel {
    case debug, info, warning, error, critical
}

// MARK: - Local Log Writer (Camera)

struct LocalLogWriter {
    static func write(level: LogLevel, message: String, subsystem: String = "booth") {
        Task.detached(priority: .background) {
            guard let url = logFileURL(subsystem: subsystem) else { return }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let tag: String
            switch level {
            case .debug: tag = "DEBUG"
            case .info: tag = "INFO"
            case .warning: tag = "WARN"
            case .error: tag = "ERROR"
            case .critical: tag = "CRIT"
            }
            let line = "[\(timestamp)] [\(tag)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func readLogContent(subsystem: String) -> String {
        guard let url = logFileURL(subsystem: subsystem),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Log file tidak ditemukan atau kosong."
        }
        return content
    }

    static func clearLog(subsystem: String) {
        guard let url = logFileURL(subsystem: subsystem) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func logFileURL(subsystem: String) -> URL? {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docsDir.appendingPathComponent("haispace_\(subsystem).log")
    }
}

// MARK: - GitHub Auto Log Uploader (Camera)

struct GitHubLogUploader {
    // PENTING: Token TIDAK boleh di-hardcode di source code.
    // GitHub Security akan otomatis merevoke token yang terekspos di public repo.
    // Token disimpan aman di iOS Keychain — input sekali, tidak perlu ulangi.
    private static let repoOwner = "izharmuh11-cyber"
    private static let repoName  = "hsp-internal"

    /// Ambil token dari Keychain. Return nil jika kosong atau format tidak valid.
    static func resolvedToken() -> String? {
        // Migrasi: jika ada di UserDefaults (versi lama), pindahkan ke Keychain lalu hapus
        if let legacy = UserDefaults.standard.string(forKey: "github_pat"),
           legacy.hasPrefix("ghp_") || legacy.hasPrefix("github_pat_") {
            KeychainHelper.saveGitHubPAT(legacy)
            UserDefaults.standard.removeObject(forKey: "github_pat")
        }
        guard let token = KeychainHelper.getGitHubPAT(), !token.isEmpty else { return nil }
        let isValid = token.hasPrefix("ghp_") || token.hasPrefix("github_pat_")
        return isValid ? token : nil
    }

    /// Simpan token baru ke Keychain (dipanggil dari UI saat user input token).
    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        return KeychainHelper.saveGitHubPAT(token)
    }

    /// Upload log ke GitHub. Completion dipanggil di main thread dengan URL file (jika sukses) atau nil.
    static func uploadLatestLog(eventName: String = "auto_event", completion: ((String?) -> Void)? = nil) {
        guard let token = resolvedToken() else { return }

        let logContent = LocalLogWriter.readLogContent(subsystem: "camera")
        guard !logContent.isEmpty && logContent != "Log file tidak ditemukan atau kosong." else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let cleanEvent = eventName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        let filename = "iphone-log-\(timestamp)-\(cleanEvent).txt"
        let apiURLString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/logs/\(filename)"
        // URL raw file yang bisa dibuka siapapun (repo public)
        let rawURLString = "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/logs/\(filename)"

        guard let url = URL(string: apiURLString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Content = Data(logContent.utf8).base64EncodedString()
        let body: [String: Any] = [
            "message": "Auto upload log from iPhone [\(cleanEvent)] at \(timestamp)",
            "content": base64Content,
            "branch": "main"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    HaispaceLogger.error("Auto upload log gagal: \(error.localizedDescription)", category: "logging")
                    completion?(nil)
                } else if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        HaispaceLogger.info("Auto upload log sukses → \(rawURLString)", category: "logging")
                        completion?(rawURLString)
                    } else {
                        HaispaceLogger.error("Auto upload log gagal dengan status: \(httpResponse.statusCode)", category: "logging")
                        completion?(nil)
                    }
                }
            }
        }.resume()
    }
}


