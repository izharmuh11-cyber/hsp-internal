// CameraLogger.swift
// HaispaceCamera — Core/Logging
//
// Logging wrapper untuk HaispaceCamera target.
// Menggunakan subsystem berbeda dari HaiBooth untuk filtering mudah di Instruments.
//
// Ref: docs/design/41_error_handling.md — Logging Pattern

import Foundation
import OSLog
import CryptoKit

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

// MARK: - R2 Log Uploader (Camera)
// Upload log ke Cloudflare R2 — tidak perlu setup token, tidak ada yang expired.
// URL public langsung bisa dibuka dan dibagikan ke AI.

struct R2LogUploader {
    // R2 credentials — developer-only, bukan user credential
    // Access key ini statis dan tidak pernah expired seperti GitHub PAT
    private static let accountID      = "66c40e0caaaa333ca0f4977bf32be2a7"
    private static let accessKeyID    = "b4612a74659f3f9ce39bd5ec1ffbefbf"
    private static let secretKey      = "388aab4ee2e7cabb97c3ac0a30a34dac2f7480628ce6afbbec6e2c730ffcbc49"
    private static let bucket         = "haispaceproject"
    private static let publicBaseURL  = "https://api.haispaceproject.my.id/r2-media"
    private static let r2Endpoint     = "https://66c40e0caaaa333ca0f4977bf32be2a7.r2.cloudflarestorage.com"

    /// Upload log kamera ke R2. Completion dipanggil di main thread dengan public URL atau nil.
    static func uploadLatestLog(eventName: String = "auto", completion: ((String?) -> Void)? = nil) {
        let logContent = LocalLogWriter.readLogContent(subsystem: "camera")
        guard !logContent.isEmpty && logContent != "Log file tidak ditemukan atau kosong." else {
            completion?(nil)
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let cleanEvent = eventName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        let uniqueKey = "haispace-logs/iphone-\(timestamp)-\(cleanEvent).txt"
        let latestKey = "haispace-logs/iphone-latest.txt"
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

        // 2. Upload ke 'iphone-latest.txt' (overwrite)
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
                    HaispaceLogger.error("R2 upload latest gagal: \(error.localizedDescription)", category: "logging")
                    completion?(nil)
                } else if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        HaispaceLogger.info("R2 upload latest sukses → \(publicLatestURL)", category: "logging")
                        completion?(publicLatestURL)
                    } else {
                        HaispaceLogger.error("R2 upload latest gagal HTTP \(http.statusCode)", category: "logging")
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



