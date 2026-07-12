// AppSecrets.swift
// HaispaceBooths / HaispaceCamera — Core/Security
//
// Hardcoded secrets (Fase 1). 
// Idealnya menggunakan CI/CD untuk menyuntikkan secrets.

import Foundation
import CommonCrypto

struct AppSecrets {
    static let qrPayloadSharedSecret = "hs_qr_secret_2026_x1y2z3"
}

struct HMACSHA256 {
    static func sign(message: String, key: String) -> String {
        guard let messageData = message.data(using: .utf8),
              let keyData = key.data(using: .utf8) else {
            return ""
        }
        
        var macData = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        messageData.withUnsafeBytes { messageBytes in
            keyData.withUnsafeBytes { keyBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBytes.baseAddress, keyData.count,
                       messageBytes.baseAddress, messageData.count,
                       &macData)
            }
        }
        
        return macData.map { String(format: "%02x", $0) }.joined()
    }
}
