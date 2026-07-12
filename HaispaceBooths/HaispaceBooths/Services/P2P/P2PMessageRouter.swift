// P2PMessageRouter.swift
// HaispaceBooths — Services/P2P
//
// Router pesan P2P berbasis AsyncStream untuk distribusi pesan secara paralel.
// Sesuai dengan Concurrency Strategy 40_concurrency_strategy.md.

import Foundation

actor P2PMessageRouter {
    
    static let shared = P2PMessageRouter()
    
    // Dictionary dari tipe pesan ke dictionary subscriber (ID: Continuation)
    private var continuations: [P2PMessageType: [String: AsyncStream<P2PMessage>.Continuation]] = [:]
    
    private init() {}
    
    /// Mendapatkan stream untuk mendengarkan pesan tipe tertentu
    func messageStream(for type: P2PMessageType) -> AsyncStream<P2PMessage> {
        AsyncStream { continuation in
            let id = UUID().uuidString
            
            if continuations[type] == nil {
                continuations[type] = [:]
            }
            continuations[type]?[id] = continuation
            
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(type: type, id: id)
                }
            }
        }
    }
    
    /// Mengirim pesan ke semua subscriber yang mendengarkan tipe pesan tersebut
    func route(_ message: P2PMessage) {
        let type = P2PMessageType.type(of: message)
        guard let subs = continuations[type] else { return }
        for continuation in subs.values {
            continuation.yield(message)
        }
    }
    
    private func removeContinuation(type: P2PMessageType, id: String) {
        continuations[type]?.removeValue(forKey: id)
        if continuations[type]?.isEmpty == true {
            continuations.removeValue(forKey: type)
        }
    }
}
