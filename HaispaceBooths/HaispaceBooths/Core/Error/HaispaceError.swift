// HaispaceError.swift
// HaispaceBooths — Core/Error
//
// Satu-satunya enum error yang boleh di-throw di seluruh codebase.
// Untuk error dari library third-party/sistem, SELALU wrap ke sini.
//
// Ref: docs/design/41_error_handling.md — Layer 1

import Foundation

// MARK: - Master Error Enum

enum HaispaceError: Error {

    // MARK: — P2P & Koneksi
    case p2pConnectionFailed(reason: P2PFailReason)
    case p2pConnectionLost
    case p2pMessageSendFailed(messageType: String)
    case p2pReconnectExhausted(attempts: Int)

    // MARK: — Kamera (AVFoundation)
    case cameraPermissionDenied
    case cameraSetupFailed(underlying: Error)
    case captureSessionInterrupted(reason: String)
    case photoCaptureFailed
    case streamingStartFailed

    // MARK: — Transfer Foto
    case thumbnailCompressionFailed(photoId: String)
    case fullQualityTransferFailed(photoId: String, attempt: Int)
    case photoDecodeFailed(photoId: String)

    // MARK: — CoreData / Penyimpanan Lokal
    case coreDataSaveFailed(entity: String, underlying: Error)
    case coreDataFetchFailed(entity: String, underlying: Error)
    case storageInsufficient(required: Int64, available: Int64)

    // MARK: — Pembayaran
    case qrisGenerationFailed(reason: String)
    case paymentTimeout(sessionId: String)

    // MARK: — Lisensi
    case licenseExpired(daysOverdue: Int)
    case licenseInvalid(reason: LicenseInvalidReason)
    case licenseDeviceLimitReached
    case licenseHeartbeatFailed
    case jailbreakDetected

    // MARK: — Cloud / Network
    case networkUnavailable
    case uploadFailed(photoId: String, httpStatus: Int?)
    case apiResponseInvalid(endpoint: String)
    case authTokenExpired
    case authTokenInvalid

    // MARK: — Filter / Rendering
    case lutFileNotFound(filterName: String)
    case lutFileParseFailed(filterName: String, reason: String)
    case filterRenderFailed(filterName: String)
    case frameCompositeFailed(frameId: String)

    // MARK: — Printer
    case printerNotFound
    case printerJobFailed(underlying: Error)

    // MARK: — System / Unknown
    case thermalThrottling(state: ProcessInfo.ThermalState)
    case unknown(underlying: Error)
}

// MARK: - Sub-Enums

enum P2PFailReason {
    case bluetoothUnavailable
    case wifiUnavailable
    case peerNotFound
    case authenticationFailed
    case timeout
}

enum LicenseInvalidReason {
    case keyNotFound
    case keyRevoked
    case deviceNotBound
    case serverUnreachable
    case checksumMismatch
}

// MARK: - Equatable Conformance
// ⚠️ PENTING: Error yang di-wrap (underlying: Error) tidak bisa otomatis Equatable.
// Kita bandingkan berdasarkan case identifier saja, bukan value-nya.

extension HaispaceError: Equatable {
    static func == (lhs: HaispaceError, rhs: HaispaceError) -> Bool {
        switch (lhs, rhs) {
        case (.p2pConnectionFailed(let a), .p2pConnectionFailed(let b)): return a == b
        case (.p2pConnectionLost, .p2pConnectionLost): return true
        case (.p2pMessageSendFailed(let a), .p2pMessageSendFailed(let b)): return a == b
        case (.p2pReconnectExhausted(let a), .p2pReconnectExhausted(let b)): return a == b
        case (.cameraPermissionDenied, .cameraPermissionDenied): return true
        case (.cameraSetupFailed, .cameraSetupFailed): return true // tidak bandingkan underlying
        case (.captureSessionInterrupted(let a), .captureSessionInterrupted(let b)): return a == b
        case (.photoCaptureFailed, .photoCaptureFailed): return true
        case (.streamingStartFailed, .streamingStartFailed): return true
        case (.thumbnailCompressionFailed(let a), .thumbnailCompressionFailed(let b)): return a == b
        case (.fullQualityTransferFailed(let a1, let a2), .fullQualityTransferFailed(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.photoDecodeFailed(let a), .photoDecodeFailed(let b)): return a == b
        case (.coreDataSaveFailed(let a, _), .coreDataSaveFailed(let b, _)): return a == b
        case (.coreDataFetchFailed(let a, _), .coreDataFetchFailed(let b, _)): return a == b
        case (.storageInsufficient(let a1, let a2), .storageInsufficient(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.qrisGenerationFailed(let a), .qrisGenerationFailed(let b)): return a == b
        case (.paymentTimeout(let a), .paymentTimeout(let b)): return a == b
        case (.licenseExpired(let a), .licenseExpired(let b)): return a == b
        case (.licenseInvalid(let a), .licenseInvalid(let b)): return a == b
        case (.licenseDeviceLimitReached, .licenseDeviceLimitReached): return true
        case (.licenseHeartbeatFailed, .licenseHeartbeatFailed): return true
        case (.jailbreakDetected, .jailbreakDetected): return true
        case (.networkUnavailable, .networkUnavailable): return true
        case (.uploadFailed(let a1, let a2), .uploadFailed(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.apiResponseInvalid(let a), .apiResponseInvalid(let b)): return a == b
        case (.authTokenExpired, .authTokenExpired): return true
        case (.authTokenInvalid, .authTokenInvalid): return true
        case (.lutFileNotFound(let a), .lutFileNotFound(let b)): return a == b
        case (.lutFileParseFailed(let a1, let a2), .lutFileParseFailed(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.filterRenderFailed(let a), .filterRenderFailed(let b)): return a == b
        case (.frameCompositeFailed(let a), .frameCompositeFailed(let b)): return a == b
        case (.printerNotFound, .printerNotFound): return true
        case (.printerJobFailed, .printerJobFailed): return true
        case (.thermalThrottling(let a), .thermalThrottling(let b)): return a == b
        case (.unknown, .unknown): return true
        default: return false
        }
    }
}

extension P2PFailReason: Equatable {}
extension LicenseInvalidReason: Equatable {}
