//
//  SupabaseAuthService.swift
//  QSkipper
//
//  Supabase Auth wrapper — mirrors the AuthManager interface
//  but routes through Supabase Auth instead of the legacy REST API.
//
//  This file is ADDITIVE — it does NOT replace AuthManager.swift.
//  To switch to Supabase auth, call these methods instead of AuthManager's.
//

import Foundation
import Supabase

@MainActor
class SupabaseAuthService: ObservableObject {

    static let shared = SupabaseAuthService()

    @Published var isLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private let userDefaultsManager = UserDefaultsManager.shared

    private init() {}

    // MARK: - Registration (replaces POST /register + POST /verify-register)

    /// Step 1: Request registration OTP.
    /// Supabase sends the OTP email automatically on signUp.
    func register(email: String, username: String, phone: String?) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await supabaseClient.auth.signUp(
                email: email,
                password: UUID().uuidString,   // dummy password — we use OTP only
                data: [
                    "username": .string(username),
                    "phone":    .string(phone ?? "")
                ]
            )
            // The on_auth_user_created trigger auto-creates profiles + wallet rows
            print("✅ SupabaseAuth: Registration OTP sent to \(email)")
        } catch {
            self.error = error.localizedDescription
            print("❌ SupabaseAuth: Registration failed — \(error)")
            throw error
        }
    }

    /// Step 2: Verify registration OTP.
    func verifyRegister(email: String, otp: String) async throws -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await supabaseClient.auth.verifyOTP(
                email: email,
                token: otp,
                type:  .signup
            )
            await syncUserToDefaults()
            isLoggedIn = true
            print("✅ SupabaseAuth: Registration verified for \(email)")
            return true
        } catch {
            self.error = error.localizedDescription
            print("❌ SupabaseAuth: Registration verification failed — \(error)")
            throw error
        }
    }

    // MARK: - Login (replaces POST /login + POST /verify-login)

    /// Step 1: Request login OTP.
    func requestLoginOTP(email: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await supabaseClient.auth.signInWithOTP(email: email)
            print("✅ SupabaseAuth: Login OTP sent to \(email)")
        } catch {
            self.error = error.localizedDescription
            print("❌ SupabaseAuth: Login OTP request failed — \(error)")
            throw error
        }
    }

    /// Step 2: Verify login OTP.
    func verifyLoginOTP(email: String, otp: String) async throws -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await supabaseClient.auth.verifyOTP(
                email: email,
                token: otp,
                type:  .magiclink
            )
            await syncUserToDefaults()
            isLoggedIn = true
            print("✅ SupabaseAuth: Login verified for \(email)")
            return true
        } catch {
            self.error = error.localizedDescription
            print("❌ SupabaseAuth: Login verification failed — \(error)")
            throw error
        }
    }

    // MARK: - Logout

    func logout() async {
        do {
            try await supabaseClient.auth.signOut()
        } catch {
            print("⚠️ SupabaseAuth: Sign-out error (non-fatal) — \(error)")
        }
        userDefaultsManager.clearUserData()
        isLoggedIn = false
        print("✅ SupabaseAuth: Logged out")
    }

    // MARK: - Session Restore (call on app launch)

    func restoreSession() async {
        do {
            _ = try await supabaseClient.auth.session
            await syncUserToDefaults()
            isLoggedIn = true
            print("✅ SupabaseAuth: Session restored")
        } catch {
            isLoggedIn = false
            print("ℹ️ SupabaseAuth: No active session")
        }
    }

    // MARK: - Resend OTP

    func resendOTP(email: String, isRegistration: Bool = false) async throws {
        if isRegistration {
            // For registration, re-trigger signUp (Supabase will resend)
            try await register(email: email, username: userDefaultsManager.getUserName() ?? "", phone: userDefaultsManager.getUserPhone())
        } else {
            try await requestLoginOTP(email: email)
        }
    }

    // MARK: - Helpers

    /// Get the current Supabase user ID.
    /// Uses UserDefaults (synced on login) to avoid async requirement.
    func getCurrentUserId() -> String? {
        userDefaultsManager.getUserId()
    }

    /// Get a valid access token for Edge Function calls.
    func getAccessToken() async throws -> String {
        let session = try await supabaseClient.auth.session
        return session.accessToken
    }

    // MARK: - Private

    /// Sync the current Supabase auth user + profile to UserDefaults
    /// so that all existing Views (ProfileView, CartView, etc.) keep working.
    private func syncUserToDefaults() async {
        guard let authUser = try? await supabaseClient.auth.user() else { return }

        // Try to fetch the extended profile from the `profiles` table
        let profile: SupabaseProfile? = try? await supabaseClient
            .from("profiles")
            .select()
            .eq("id", value: authUser.id.uuidString.lowercased())
            .single()
            .execute()
            .value

        // Extract username and phone from metadata
        let metaUsername = (authUser.userMetadata["username"] as? AnyJSON).flatMap { val -> String? in
            if case .string(let s) = val { return s }
            return nil
        }
        let metaPhone = (authUser.userMetadata["phone"] as? AnyJSON).flatMap { val -> String? in
            if case .string(let s) = val { return s }
            return nil
        }

        // Get access token (async-safe since we're already in an async context)
        let accessToken: String? = try? await supabaseClient.auth.session.accessToken

        // Build a User struct that matches the existing model in AuthModels.swift
        let user = User(
            id:       authUser.id.uuidString.lowercased(),
            email:    authUser.email ?? "",
            name:     profile?.username ?? metaUsername ?? "",
            phone:    profile?.phone ?? metaPhone ?? "",
            token:    accessToken
        )

        userDefaultsManager.saveUser(user)
        print("✅ SupabaseAuth: Synced user to UserDefaults — id=\(user.id), name=\(user.name ?? "nil")")
    }
}

// MARK: - Profile row from Supabase `profiles` table

/// Internal Codable struct for decoding the `profiles` table row.
/// This is NOT the same as the migration guide's `Profile` — it matches
/// the actual `profiles` table created by 01_supabase_customer_schema_patch.sql.
private struct SupabaseProfile: Codable {
    let id: String
    let username: String
    let phone: String?
    let created_at: String?
    let updated_at: String?
}

