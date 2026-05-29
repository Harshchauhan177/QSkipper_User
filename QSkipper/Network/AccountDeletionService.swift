//
//  AccountDeletionService.swift
//  QSkipper
//
//  Self-contained service for account deletion via the `delete-account` Edge Function.
//  This file is ADDITIVE — it does NOT modify or replace any existing file.
//

import Foundation

@MainActor
class AccountDeletionService {

    static let shared = AccountDeletionService()

    private var edgeFunctionBase: String {
        "\(SupabaseConfig.url.absoluteString)/functions/v1"
    }

    private init() {}

    // MARK: - Delete Account

    /// Calls the `delete-account` Edge Function, then clears the local session.
    /// Throws if the network call or server-side deletion fails.
    func deleteAccount() async throws {
        // 1. Get the current access token
        let token = try await SupabaseAuthService.shared.getAccessToken()

        // 2. Call the Edge Function
        let response: DeleteAccountResponse = try await callEdgeFunction(
            name: "delete-account",
            token: token
        )

        guard response.success else {
            let message = response.message ?? "Account deletion failed on the server."
            throw NSError(
                domain: "AccountDeletionService",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        // 3. Sign out locally (clears Supabase session + UserDefaults + Keychain)
        await SupabaseAuthService.shared.logout()

        print("✅ AccountDeletionService: Account deleted and local session cleared")
    }

    // MARK: - Private: Edge Function Caller

    /// Calls the `delete-account` Edge Function via URLSession.
    /// Follows the same pattern as SupabaseOrderService.callEdgeFunction.
    private func callEdgeFunction<T: Decodable>(
        name: String,
        token: String
    ) async throws -> T {
        guard let url = URL(string: "\(edgeFunctionBase)/\(name)") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])  // empty body

        print("📡 AccountDeletionService: Calling edge function \(name)")

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📩 AccountDeletionService: \(name) response (\(http.statusCode)): \(responseString)")
        }

        guard (200...299).contains(http.statusCode) else {
            // Try to extract a user-friendly error message
            let errorMsg: String
            if let errResp = try? JSONDecoder().decode(DeleteAccountResponse.self, from: data) {
                errorMsg = errResp.message ?? "Unknown error"
            } else {
                errorMsg = "Server error \(http.statusCode)"
            }
            throw NSError(
                domain: "AccountDeletionService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMsg]
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Response Model

/// Response from the `delete-account` Edge Function.
private struct DeleteAccountResponse: Codable {
    let success: Bool
    let message: String?
}
