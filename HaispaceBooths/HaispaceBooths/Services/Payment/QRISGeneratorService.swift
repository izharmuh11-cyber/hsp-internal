// QRISGeneratorService.swift
// HaispaceBooths — Services/Payment
//
// Generator QRIS EMVCo offline.
// Membuat payload string QRIS secara lokal dengan menghitung checksum CRC16 (CCITT-False).
//
// Ref: docs/design/33_local_qris.md

import Foundation

enum QRISGeneratorError: Error {
    case invalidMerchantData
    case generationFailed
}

final class QRISGeneratorService {
    
    /// Konfigurasi statis merchant (Harus diisi dengan data QRIS Haispace asli)
    struct MerchantConfig {
        let globalUniqueIdentifier: String
        let merchantId: String
        let criteria: String
        let merchantName: String
        let merchantCity: String
        let postalCode: String
    }
    
    // Mock config untuk Fase 2
    static let defaultConfig = MerchantConfig(
        globalUniqueIdentifier: "ID.CO.QRIS.WWW",
        merchantId: "ID10203040506070809", // Contoh Nnmid
        criteria: "UMI",
        merchantName: "HAISPACE PHOTOBOOTH",
        merchantCity: "JAKARTA SELATAN",
        postalCode: "12345"
    )
    
    /// Men-generate raw QRIS string berdasarkan amount secara dinamis
    static func generate(amount: Int, transactionId: String, config: MerchantConfig = defaultConfig) throws -> String {
        guard amount > 0 else { throw QRISGeneratorError.invalidMerchantData }
        
        var payload = ""
        
        // Helper untuk memformat TLV (Tag, Length, Value)
        func appendTLV(tag: String, value: String) {
            let length = String(format: "%02d", value.count)
            payload += "\(tag)\(length)\(value)"
        }
        
        // 00: Payload Format Indicator
        appendTLV(tag: "00", value: "01")
        
        // 01: Point of Initiation Method (11 = Static, 12 = Dynamic)
        appendTLV(tag: "01", value: "12")
        
        // 26-51: Merchant Account Information
        var merchantAccountInfo = ""
        merchantAccountInfo += "00\(String(format: "%02d", config.globalUniqueIdentifier.count))\(config.globalUniqueIdentifier)"
        merchantAccountInfo += "01\(String(format: "%02d", config.merchantId.count))\(config.merchantId)"
        merchantAccountInfo += "02\(String(format: "%02d", config.merchantId.count))\(config.merchantId)"
        merchantAccountInfo += "03\(String(format: "%02d", config.criteria.count))\(config.criteria)"
        appendTLV(tag: "26", value: merchantAccountInfo)
        
        // 52: Merchant Category Code
        appendTLV(tag: "52", value: "5999")
        
        // 53: Transaction Currency (360 = IDR)
        appendTLV(tag: "53", value: "360")
        
        // 54: Transaction Amount
        appendTLV(tag: "54", value: "\(amount)")
        
        // 58: Country Code
        appendTLV(tag: "58", value: "ID")
        
        // 59: Merchant Name
        appendTLV(tag: "59", value: config.merchantName)
        
        // 60: Merchant City
        appendTLV(tag: "60", value: config.merchantCity)
        
        // 61: Postal Code
        appendTLV(tag: "61", value: config.postalCode)
        
        // 62: Additional Data Field (Transaction ID / Bill Number)
        let billNumber = "01\(String(format: "%02d", transactionId.count))\(transactionId)"
        appendTLV(tag: "62", value: billNumber)
        
        // 63: CRC (Checksum)
        payload += "6304"
        
        // Hitung CRC16 dari payload sampai "6304"
        let crc = calculateCRC16(data: Array(payload.utf8))
        payload += String(format: "%04X", crc)
        
        return payload
    }
    
    /// Menginjeksi nominal ke dalam QRIS string EMVCo statis dan menghitung ulang CRC16
    static func generate(from merchantString: String, amount: Int, transactionId: String) throws -> String {
        guard amount > 0 else { throw QRISGeneratorError.invalidMerchantData }
        var base = merchantString
        
        // 1. Ubah field "010211" (static) ke "010212" (dynamic)
        base = base.replacingOccurrences(of: "010211", with: "010212")
        
        // 2. Inject field 54 (Transaction Amount) sebelum tag 58 (Country Code)
        let amountStr = String(amount)
        let amountField = "54\(String(format: "%02d", amountStr.count))\(amountStr)"
        
        if let range = base.range(of: "5802") {
            base.insert(contentsOf: amountField, at: range.lowerBound)
        } else {
            throw QRISGeneratorError.invalidMerchantData
        }
        
        // 3. Inject field 62 (Additional Data / Bill Number) sebelum tag 63 (CRC, "6304")
        let billNumberVal = "01\(String(format: "%02d", transactionId.count))\(transactionId)"
        let field62 = "62\(String(format: "%02d", billNumberVal.count))\(billNumberVal)"
        
        if let range = base.range(of: "6304") {
            base.insert(contentsOf: field62, at: range.lowerBound)
        }
        
        // Hapus 4 karakter CRC lama dan tambahkan prefix "6304"
        let withoutCRC = String(base.dropLast(4))
        let targetPayload = withoutCRC.hasSuffix("6304") ? withoutCRC : withoutCRC + "6304"
        
        // Hitung CRC16-CCITT
        let crc = calculateCRC16(data: Array(targetPayload.utf8))
        let crcHex = String(format: "%04X", crc)
        
        return targetPayload + crcHex
    }
    
    // MARK: - CRC16 CCITT-False Implementation
    
    private static func calculateCRC16(data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF // Initial value untuk CCITT-False
        let polynomial: UInt16 = 0x1021 // Polynomial
        
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ polynomial
                } else {
                    crc <<= 1
                }
            }
        }
        
        return crc & 0xFFFF
    }
}
