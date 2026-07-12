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
    static func uploadLatestLog(eventName: String = "auto_event") {
        guard let token = UserDefaults.standard.string(forKey: "github_pat"), !token.isEmpty else {
            HaispaceLogger.warning("Auto log upload dilewati: token PAT kosong. Silakan masukkan token Anda di menu Log Sistem.", category: "logging")
            return
        }
        
        let logContent = LocalLogWriter.readLogContent(subsystem: "camera")
        guard !logContent.isEmpty && logContent != "Log file tidak ditemukan atau kosong." else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        
        // Clean event name for safe filename
        let cleanEvent = eventName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            
        let filename = "iphone-log-\(timestamp)-\(cleanEvent).txt"
        
        guard let url = URL(string: "https://api.github.com/repos/izharmuh11-cyber/hsp-internal/contents/logs/\(filename)") else {
            HaispaceLogger.error("Gagal membuat URL untuk upload log: \(filename)", category: "logging")
            return
        }
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
            if let error = error {
                HaispaceLogger.error("Auto upload log gagal: \(error.localizedDescription)", category: "logging")
            } else if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    HaispaceLogger.info("Auto upload log sukses! File: \(filename)", category: "logging")
                } else {
                    HaispaceLogger.error("Auto upload log gagal dengan status: \(httpResponse.statusCode)", category: "logging")
                }
            }
        }.resume()
    }
}

