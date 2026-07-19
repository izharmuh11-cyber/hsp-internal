// AuthService.swift
// HaispaceBooths — Services
//
// Service layer untuk autentikasi ke Haispace API.
// Fase 0: Implementasi stub/mock untuk development.
// Fase 3: Replace dengan implementasi HTTP nyata ke https://api.haispace.id
//
// Ref: docs/design/30_authentication.md
// Ref: docs/design/32_server_infrastructure.md

import Foundation

// MARK: - AuthService Protocol

protocol AuthServiceProtocol {
    func login(email: String, password: String) async throws -> HaispaceUser
    func validateToken(_ token: String) async throws -> HaispaceUser
    func logout(token: String) async throws
}

// MARK: - AuthService

/// Singleton service untuk semua operasi autentikasi.
/// Gunakan `AuthService.shared` — jangan buat instance baru.
final class AuthService {

    static let shared: any AuthServiceProtocol = {
        #if DEBUG
        return MockAuthService()
        #else
        return LiveAuthService()
        #endif
    }()

    private init() {}
}

// MARK: - Live Auth Service (Production)

final class LiveAuthService: AuthServiceProtocol {

    private let baseURL = "https://api.haispace.id"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func login(email: String, password: String) async throws -> HaispaceUser {
        guard let url = URL(string: "\(baseURL)/auth/login") else {
            throw HaispaceError.apiResponseInvalid(endpoint: "/auth/login")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HaispaceError.apiResponseInvalid(endpoint: "/auth/login")
            }

            switch httpResponse.statusCode {
            case 200:
                let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
                // Simpan JWT token ke Keychain
                KeychainHelper.saveAuthToken(loginResponse.token)
                return loginResponse.user
            case 401:
                throw HaispaceError.authTokenInvalid
            case 403:
                throw HaispaceError.licenseInvalid(reason: .keyRevoked)
            default:
                throw HaispaceError.apiResponseInvalid(endpoint: "/auth/login")
            }
        } catch let error as HaispaceError {
            throw error
        } catch {
            throw HaispaceError.networkUnavailable
        }
    }

    func validateToken(_ token: String) async throws -> HaispaceUser {
        guard let url = URL(string: "\(baseURL)/auth/me") else {
            throw HaispaceError.apiResponseInvalid(endpoint: "/auth/me")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HaispaceError.apiResponseInvalid(endpoint: "/auth/me")
            }

            switch httpResponse.statusCode {
            case 200:
                return try JSONDecoder().decode(HaispaceUser.self, from: data)
            case 401:
                throw HaispaceError.authTokenExpired
            default:
                throw HaispaceError.apiResponseInvalid(endpoint: "/auth/me")
            }
        } catch let error as HaispaceError {
            throw error
        } catch {
            throw HaispaceError.networkUnavailable
        }
    }

    func logout(token: String) async throws {
        // Fire and forget — tidak kritis jika gagal
        guard let url = URL(string: "\(baseURL)/auth/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }
}

// MARK: - Mock Auth Service (Development / Preview)

final class MockAuthService: AuthServiceProtocol {

    // Simulasi delay network
    private let simulatedDelay: Duration = .milliseconds(800)

    func login(email: String, password: String) async throws -> HaispaceUser {
        try? await Task.sleep(for: simulatedDelay)

        // Validasi mock credentials
        if (email == "123" || email == "izhar@haispace.id" || email == "budi@haispace.id") && (password == "123" || password == "admin123" || password == "operator123") {
            let token = "mock-jwt-operator-\(UUID().uuidString)"
            KeychainHelper.saveAuthToken(token)
            return .mockOperator
        }

        // Gagal login
        throw HaispaceError.authTokenInvalid
    }

    func validateToken(_ token: String) async throws -> HaispaceUser {
        try? await Task.sleep(for: simulatedDelay)

        guard !token.isEmpty else {
            throw HaispaceError.authTokenExpired
        }

        // Mock: token admin
        if token.contains("admin") {
            return .mockAdmin
        }
        // Mock: token operator
        return .mockOperator
    }

    func logout(token: String) async throws {
        // Mock: tidak melakukan apa-apa
        HaispaceLogger.debug("MockAuthService: logout dipanggil")
    }
}

// MARK: - Login Response Model

private struct LoginResponse: Codable {
    let token: String
    let user: HaispaceUser
}
