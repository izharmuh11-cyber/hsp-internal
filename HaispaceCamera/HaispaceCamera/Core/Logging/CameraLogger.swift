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

    static func logFileURL(subsystem: String) -> URL? {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docsDir.appendingPathComponent("haispace_\(subsystem).log")
    }
}
