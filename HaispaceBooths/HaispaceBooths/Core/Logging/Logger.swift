// Logger.swift
// HaispaceBooths — Core/Logging
//
// Satu-satunya cara logging yang diizinkan di seluruh codebase.
// Jangan gunakan print() untuk error — tidak masuk ke crash report.
//
// Ref: docs/design/41_error_handling.md — Logging Pattern

import Foundation
import OSLog
import CryptoKit

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

// MARK: - R2 Log Uploader
// Upload log ke Cloudflare R2 — credentials dibaca dari AppSecretConfig (xcconfig).
// Tidak ada hardcoded credential di sini. Lihat: Core/Security/AppSecrets.swift

struct R2LogUploader {

    /// Upload log booth ke R2. Completion dipanggil di main thread dengan public URL atau nil.
    static func uploadLatestLog(eventName: String = "auto", completion: ((String?) -> Void)? = nil) {
        let logContent = LocalLogWriter.readLogContent()
        guard !logContent.isEmpty && logContent != "Log file tidak ditemukan atau kosong." else {
            completion?(nil)
            return
        }

        // Baca credentials dari AppSecretConfig (xcconfig → Info.plist → runtime)
        _ = AppSecretConfig.R2.accountID // Not used in signing logic below
        let accessKeyID  = AppSecretConfig.R2.accessKeyID
        let secretKey    = AppSecretConfig.R2.secretKey
        let bucket       = AppSecretConfig.R2.bucket
        let publicBaseURL = AppSecretConfig.R2.publicBaseURL
        let r2Endpoint   = AppSecretConfig.R2.endpoint

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let cleanEvent = eventName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        let uniqueKey = "haispace-logs/ipad-\(timestamp)-\(cleanEvent).txt"
        let latestKey = "haispace-logs/ipad-latest.txt"
        let publicLatestURL = "\(publicBaseURL)/\(latestKey)"

        guard let body = logContent.data(using: .utf8) else {
            completion?(nil)
            return
        }

        // 1. Upload ke unique timestamped file
        let uniqueRequest = AWSV4Signer.sign(
            method: "PUT",
            endpoint: r2Endpoint,
            bucket: bucket,
            key: uniqueKey,
            body: body,
            contentType: "text/plain; charset=utf-8",
            accessKeyID: accessKeyID,
            secretKey: secretKey,
            region: "auto",
            service: "s3"
        )
        URLSession.shared.dataTask(with: uniqueRequest).resume()

        // 2. Upload ke 'ipad-latest.txt' (overwrite)
        let latestRequest = AWSV4Signer.sign(
            method: "PUT",
            endpoint: r2Endpoint,
            bucket: bucket,
            key: latestKey,
            body: body,
            contentType: "text/plain; charset=utf-8",
            accessKeyID: accessKeyID,
            secretKey: secretKey,
            region: "auto",
            service: "s3"
        )

        URLSession.shared.dataTask(with: latestRequest) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    HaispaceLogger.warning("R2 upload latest gagal: \(error.localizedDescription)", category: "logging")
                    completion?(nil)
                } else if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        HaispaceLogger.info("R2 upload latest sukses → \(publicLatestURL)", category: "logging")
                        completion?(publicLatestURL)
                    } else {
                        HaispaceLogger.warning("R2 upload latest gagal HTTP \(http.statusCode)", category: "logging")
                        completion?(nil)
                    }
                }
            }
        }.resume()
    }
}


// MARK: - AWS Signature V4 (minimal, no external dependency)
// Implementasi minimal AWS SigV4 untuk S3-compatible PUT request.
// Dipakai untuk auth ke Cloudflare R2 (S3-compatible API).

import CryptoKit

enum AWSV4Signer {
    static func sign(
        method: String,
        endpoint: String,
        bucket: String,
        key: String,
        body: Data,
        contentType: String,
        accessKeyID: String,
        secretKey: String,
        region: String,
        service: String
    ) -> URLRequest {
        let urlString = "\(endpoint)/\(bucket)/\(key)"
        guard let url = URL(string: urlString) else {
            fatalError("Invalid R2 URL: \(urlString)")
        }

        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay,
                                       .withTime, .withTimeZone, .withColonSeparatorInTime]
        let amzDate = dateFormatter.string(from: now)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        // amzDate format: 20260718T090000Z
        let dateStamp = String(amzDate.prefix(8))  // 20260718

        let bodyHash = SHA256.hash(data: body).compactMap { String(format: "%02x", $0) }.joined()

        // Canonical headers (harus sorted alphabetical)
        let host = URL(string: endpoint)!.host!
        let canonicalHeaders =
            "content-type:\(contentType)\n" +
            "host:\(host)\n" +
            "x-amz-content-sha256:\(bodyHash)\n" +
            "x-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

        let encodedKey = key
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let canonicalURI = "/\(bucket)/\(encodedKey)"

        let canonicalRequest =
            method + "\n" +
            canonicalURI + "\n" +
            "" + "\n" +  // query string kosong
            canonicalHeaders + "\n" +
            signedHeaders + "\n" +
            bodyHash

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalHash = SHA256.hash(data: Data(canonicalRequest.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()

        let stringToSign =
            "AWS4-HMAC-SHA256" + "\n" +
            amzDate + "\n" +
            credentialScope + "\n" +
            canonicalHash

        // Derive signing key
        func hmac256(_ key: Data, _ data: String) -> Data {
            let symKey = SymmetricKey(data: key)
            let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: symKey)
            return Data(mac)
        }
        let signingKey = hmac256(
            hmac256(
                hmac256(
                    hmac256(Data(("AWS4" + secretKey).utf8), dateStamp),
                    region
                ),
                service
            ),
            "aws4_request"
        )

        let symKey = SymmetricKey(data: signingKey)
        let signatureMac = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: symKey)
        let signature = Data(signatureMac).compactMap { String(format: "%02x", $0) }.joined()

        let authHeader =
            "AWS4-HMAC-SHA256 " +
            "Credential=\(accessKeyID)/\(credentialScope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(bodyHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        return request
    }
}
