// AppSecrets.swift
// HaispaceBooths / HaispaceCamera — Core/Security
//
// Hardcoded secrets (Fase 1). 
// Idealnya menggunakan CI/CD untuk menyuntikkan secrets.

import Foundation
import CryptoKit

struct AppSecrets {
    static let qrPayloadSharedSecret = "hs_qr_secret_2026_x1y2z3"
}

struct HMACSHA256 {
    static func sign(message: String, key: String) -> String {
        guard let messageData = message.data(using: .utf8),
              let keyData = key.data(using: .utf8) else {
            return ""
        }
        
        let symmetricKey = SymmetricKey(data: keyData)
        let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)
        return signature.compactMap { String(format: "%02x", $0) }.joined()
    }
}
