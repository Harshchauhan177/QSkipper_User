//
//  SupabaseManager.swift
//  QSkipper
//
//  Supabase client singleton.
//  This file is ADDITIVE — it does NOT replace any existing file.
//

import Foundation
import Supabase

// MARK: - Configuration
enum SupabaseConfig {
    static let url     = URL(string: "https://bhxhjsandxjairzccbqk.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJoeGhqc2FuZHhqYWlyemNjYnFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyOTQ2NzIsImV4cCI6MjA5Mzg3MDY3Mn0.fvyI2DPxsvNDTvTUq-MIluMYjwPeQO_7CrDMatjLLrI"
}

// MARK: - Shared Supabase Client
/// Single shared SupabaseClient instance — use `supabaseClient` anywhere in the app.
/// This does NOT interfere with the existing APIClient / NetworkUtils / ServerConfig.
let supabaseClient = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
