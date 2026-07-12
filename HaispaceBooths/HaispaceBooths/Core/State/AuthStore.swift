// AuthStore.swift
// HaispaceBooths — Core/State
//
// Store untuk status autentikasi operator/admin.
// Mengelola login, logout, dan status JWT token.
//
// ATURAN:
// - Semua modifikasi state harus di @MainActor
// - Gunakan @Observable, BUKAN ObservableObject/@Published
// - Store tidak memanggil service di init (mencegah side effect di Preview)
//
// Ref: docs/design/39_state_architecture.md — AuthStore
// Ref: docs/design/30_authentication.md

import Foundation
import Observation

// MARK: - AuthStatus

/// Status autentikasi operator
/// Menggunakan String untuk error (bukan Error) agar Equatable bisa bekerja.
/// Ref: 39_state_architecture.md — catatan Equatable
enum AuthStatus: Equatable {
    case unauthenticated
    case loading
    case authenticated
    case failed(String) // String = error.localizedDescription (bukan Error)
}

// MARK: - AuthStore

@Observable
final class AuthStore {

    // MARK: State
    var currentUser: HaispaceUser?
    var authStatus: AuthStatus = .unauthenticated

    // MARK: Computed

    var isLoggedIn: Bool { currentUser != nil }
    var userRole: UserRole { currentUser?.role ?? .operator }
    var isAdmin: Bool { currentUser?.role == .admin }

    // MARK: - Actions

    /// Login dengan email & password — validasi ke server Haispace
    @MainActor
    func login(email: String, password: String) async throws {
        guard authStatus != .loading else { return }
        authStatus = .loading

        do {
            let user = try await AuthService.shared.login(email: email, password: password)
            currentUser = user
            authStatus = .authenticated
            HaispaceLogger.info("Login berhasil: \(user.email) [\(user.role.displayName)]", category: "auth")
        } catch {
            let errorMessage = error.localizedDescription
            authStatus = .failed(errorMessage)
            throw error
        }
    }

    /// Logout — hapus user dari memori dan token dari Keychain
    @MainActor
    func logout() {
        HaispaceLogger.info("Logout: \(currentUser?.email ?? "unknown")", category: "auth")
        currentUser = nil
        authStatus = .unauthenticated
        KeychainHelper.deleteAuthToken()
    }

    /// Coba restore session dari token yang tersimpan di Keychain
    @MainActor
    func restoreSession() async {
        guard let token = KeychainHelper.getAuthToken() else {
            HaispaceLogger.info("Tidak ada session tersimpan — perlu login", category: "auth")
            return
        }

        authStatus = .loading
        do {
            let user = try await AuthService.shared.validateToken(token)
            currentUser = user
            authStatus = .authenticated
            HaispaceLogger.info("Session di-restore: \(user.email)", category: "auth")
        } catch {
            // Token expired atau invalid — bersihkan
            HaispaceLogger.warning("Session restore gagal: \(error.localizedDescription)", category: "auth")
            KeychainHelper.deleteAuthToken()
            authStatus = .unauthenticated
        }
    }
}
