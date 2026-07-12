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
    
    struct TLV {
        let tag: String
        var value: String
    }
    
    private static func parseTLV(_ string: String) -> [TLV] {
        var tlvs: [TLV] = []
        var index = string.startIndex
        while index < string.endIndex {
            // Baca Tag (2 karakter)
            guard let nextTagIndex = string.index(index, offsetBy: 2, limitedBy: string.endIndex) else { break }
            let tag = String(string[index..<nextTagIndex])
            index = nextTagIndex
            
            // Baca Length (2 karakter)
            guard let nextLengthIndex = string.index(index, offsetBy: 2, limitedBy: string.endIndex) else { break }
            let lengthStr = String(string[index..<nextLengthIndex])
            guard let length = Int(lengthStr) else { break }
            index = nextLengthIndex
            
            // Baca Value (panjang karakter sesuai length)
            guard let nextValueIndex = string.index(index, offsetBy: length, limitedBy: string.endIndex) else { break }
            let value = String(string[index..<nextValueIndex])
            index = nextValueIndex
            
            tlvs.append(TLV(tag: tag, value: value))
        }
        return tlvs
    }
    
    private static func encodeTLV(_ tlvs: [TLV]) -> String {
        var result = ""
        for tlv in tlvs {
            let lengthStr = String(format: "%02d", tlv.value.count)
            result += tlv.tag + lengthStr + tlv.value
        }
        return result
    }

    /// Menginjeksi nominal ke dalam QRIS string EMVCo statis dan menghitung ulang CRC16
    static func generate(from merchantString: String, amount: Int, transactionId: String) throws -> String {
        guard amount > 0 else { throw QRISGeneratorError.invalidMerchantData }
        
        // Parse raw merchant string ke struktur TLV
        var tlvs = parseTLV(merchantString)
        
        // 1. Ubah Tag "01" (Point of Initiation Method) dari "11" (Static) ke "12" (Dynamic)
        if let idx = tlvs.firstIndex(where: { $0.tag == "01" }) {
            if tlvs[idx].value == "11" {
                tlvs[idx].value = "12"
            }
        } else {
            if let idx00 = tlvs.firstIndex(where: { $0.tag == "00" }) {
                tlvs.insert(TLV(tag: "01", value: "12"), at: idx00 + 1)
            } else {
                tlvs.insert(TLV(tag: "01", value: "12"), at: 0)
            }
        }
        
        // 2. Set/Update Tag "54" (Transaction Amount)
        let amountStr = String(amount)
        if let idx = tlvs.firstIndex(where: { $0.tag == "54" }) {
            tlvs[idx].value = amountStr
        } else {
            // Sisipkan Tag 54 sebelum Tag 58 (Country Code) jika ada, jika tidak sebelum Tag 59, dll.
            if let idx58 = tlvs.firstIndex(where: { $0.tag == "58" }) {
                tlvs.insert(TLV(tag: "54", value: amountStr), at: idx58)
            } else if let idx59 = tlvs.firstIndex(where: { $0.tag == "59" }) {
                tlvs.insert(TLV(tag: "54", value: amountStr), at: idx59)
            } else {
                if let idx63 = tlvs.firstIndex(where: { $0.tag == "63" }) {
                    tlvs.insert(TLV(tag: "54", value: amountStr), at: idx63)
                } else {
                    tlvs.append(TLV(tag: "54", value: amountStr))
                }
            }
        }
        
        // 3. Set/Update Tag "62" (Additional Data / Bill Number)
        let billNumberVal = "01\(String(format: "%02d", transactionId.count))\(transactionId)"
        if let idx = tlvs.firstIndex(where: { $0.tag == "62" }) {
            tlvs[idx].value = billNumberVal
        } else {
            if let idx63 = tlvs.firstIndex(where: { $0.tag == "63" }) {
                tlvs.insert(TLV(tag: "62", value: billNumberVal), at: idx63)
            } else {
                tlvs.append(TLV(tag: "62", value: billNumberVal))
            }
        }
        
        // 4. Hapus Tag 63 lama (jika ada) untuk dihitung ulang
        tlvs.removeAll(where: { $0.tag == "63" })
        
        // Encode kembali seluruh TLV ke format String
        var basePayload = encodeTLV(tlvs)
        
        // Tambahkan Tag 63 dengan length 04 untuk dihitung checksum-nya
        basePayload += "6304"
        
        // Hitung CRC16-CCITT
        let crc = calculateCRC16(data: Array(basePayload.utf8))
        let crcHex = String(format: "%04X", crc)
        
        return basePayload + crcHex
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
