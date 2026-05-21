//
//  SupabaseOrderService.swift
//  QSkipper
//
//  Handles order placement (via Edge Functions) and order queries (via PostgREST).
//  Returns the EXISTING UserOrder / UserOrderItem model types.
//
//  This file is ADDITIVE — it does NOT replace OrderAPIService.swift or OrderManager.swift.
//

import Foundation
import Supabase

class SupabaseOrderService {

    static let shared = SupabaseOrderService()

    private var edgeFunctionBase: String {
        "\(SupabaseConfig.url.absoluteString)/functions/v1"
    }

    private init() {}

    // MARK: - Place Order (calls Edge Function: place-order)
    // Replaces: POST /order-placed

    /// Place an immediate order. Returns the new order's UUID string.
    func placeOrder(
        restaurantId: String,
        userId:       String,
        items:        [[String: Any]],
        price:        String,
        takeAway:     Bool
    ) async throws -> SBPlaceOrderResponse {
        let token = try await SupabaseAuthService.shared.getAccessToken()
        let body: [String: Any] = [
            "restaurantId": restaurantId,
            "userId":       userId,
            "items":        items,
            "price":        price,
            "takeAway":     takeAway
        ]
        return try await callEdgeFunction(
            name:  "place-order",
            body:  body,
            token: token
        )
    }

    // MARK: - Schedule Order (calls Edge Function: schedule-order)
    // Replaces: POST /schedule-order-placed

    /// Place a scheduled order. Returns the new order's UUID string.
    func placeScheduledOrder(
        restaurantId: String,
        userId:       String,
        items:        [[String: Any]],
        price:        String,
        scheduleDate: String
    ) async throws -> SBPlaceOrderResponse {
        let token = try await SupabaseAuthService.shared.getAccessToken()
        let body: [String: Any] = [
            "restaurantId": restaurantId,
            "userId":       userId,
            "items":        items,
            "price":        price,
            "takeAway":     true,            // always true for scheduled orders
            "scheduleDate": scheduleDate
        ]
        return try await callEdgeFunction(
            name:  "schedule-order",
            body:  body,
            token: token
        )
    }

    // MARK: - Verify Order (calls Edge Function: verify-order)
    // Replaces: POST /verify-order

    /// Confirm an order after successful payment (or COD).
    func verifyOrder(orderId: String) async throws {
        let token = try await SupabaseAuthService.shared.getAccessToken()
        let body: [String: Any] = ["order_id": orderId]
        let _: SBGenericResponse = try await callEdgeFunction(
            name:  "verify-order",
            body:  body,
            token: token
        )
        print("✅ SupabaseOrderService: Order \(orderId) verified")
    }

    // MARK: - Cancel Order (calls Edge Function: cancel-order)
    // Replaces: POST /cancel-order

    /// Cancel an order (only if status is pending/placed/schedule).
    func cancelOrder(orderId: String) async throws {
        let token = try await SupabaseAuthService.shared.getAccessToken()
        let body: [String: Any] = ["order_id": orderId]
        let _: SBGenericResponse = try await callEdgeFunction(
            name:  "cancel-order",
            body:  body,
            token: token
        )
        print("✅ SupabaseOrderService: Order \(orderId) cancelled")
    }

    // MARK: - Get User Orders (direct PostgREST query)
    // Replaces: GET /get-user-orders/:userId

    /// Fetch all orders for the current user.
    /// Returns the existing `UserOrder` model defined in UserOrdersView.swift.
    func fetchUserOrders(userId: String) async throws -> [UserOrder] {
        let rows: [SBOrderRow] = try await supabaseClient
            .from("orders")
            .select("""
                id, restaurant_id, user_id, total_amount, status,
                cook_time, take_away, schedule_date, order_time, rating,
                restaurants ( name, location ),
                order_items ( id, product_id, name, quantity, price )
            """)
            .eq("user_id", value: userId)
            .order("order_time", ascending: false)
            .execute()
            .value

        print("✅ SupabaseOrderService: Fetched \(rows.count) orders for user \(userId)")
        return rows.map { $0.toUserOrder() }
    }

    // MARK: - Submit Rating (direct PostgREST update on orders table)

    /// Submit a rating (1–5) for a completed order.
    func submitRating(orderId: String, rating: Int) async throws {
        struct RatingUpdate: Encodable {
            let rating: Int
        }
        struct RatingRow: Decodable {
            let rating: Int?
        }
        
        // Perform the update
        try await supabaseClient
            .from("orders")
            .update(RatingUpdate(rating: rating))
            .eq("id", value: orderId)
            .execute()
        
        // Verify the update actually persisted (RLS can silently block writes)
        let rows: [RatingRow] = try await supabaseClient
            .from("orders")
            .select("rating")
            .eq("id", value: orderId)
            .execute()
            .value
        
        guard let saved = rows.first?.rating, saved == rating else {
            print("❌ SupabaseOrderService: Rating update was silently blocked (likely RLS policy missing)")
            throw NSError(
                domain: "SupabaseOrderService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Rating could not be saved. Please check database permissions."]
            )
        }
        
        print("✅ SupabaseOrderService: Submitted and verified rating \(rating) for order \(orderId)")
    }

    // MARK: - Get Order Status (direct PostgREST query)
    // Replaces: GET /order-status/:orderId

    /// Fetch the current status of a specific order.
    func fetchOrderStatus(orderId: String) async throws -> String {
        struct StatusRow: Codable { let status: String }
        let row: StatusRow = try await supabaseClient
            .from("orders")
            .select("status")
            .eq("id", value: orderId)
            .single()
            .execute()
            .value
        return row.status
    }

    // MARK: - Private: Edge Function Caller

    /// Generic helper to call a Supabase Edge Function via URLSession.
    /// Using URLSession directly (instead of supabaseClient.functions.invoke)
    /// for maximum compatibility and control over error handling.
    private func callEdgeFunction<T: Decodable>(
        name:  String,
        body:  [String: Any],
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
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("📡 SupabaseOrderService: Calling edge function \(name)")

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Log the response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📩 SupabaseOrderService: \(name) response (\(http.statusCode)): \(responseString)")
        }

        guard (200...299).contains(http.statusCode) else {
            // Try to extract a user-friendly error message
            let errorMsg: String
            if let errResp = try? JSONDecoder().decode(SBErrorResponse.self, from: data) {
                errorMsg = errResp.message ?? "Unknown error"
            } else {
                errorMsg = "Server error \(http.statusCode)"
            }
            throw NSError(
                domain: "SupabaseEdgeFunction",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMsg]
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}


// ============================================================
// MARK: - Response Models
// ============================================================

/// Response from place-order / schedule-order edge functions.
struct SBPlaceOrderResponse: Codable {
    let success: Bool
    let data: SBOrderData?

    struct SBOrderData: Codable {
        let orderId: String
    }

    /// Convenience accessor for the order ID.
    var orderId: String? { data?.orderId }
}

/// Generic success/failure response from edge functions.
struct SBGenericResponse: Codable {
    let success: Bool
    let message: String?
}

/// Error response from edge functions.
private struct SBErrorResponse: Codable {
    let success: Bool?
    let message: String?
}


// ============================================================
// MARK: - Codable Row Struct (maps Supabase → existing UserOrder model)
// ============================================================

/// Matches a joined query on `orders` + `restaurants` + `order_items`.
private struct SBOrderRow: Codable {
    let id:              String
    let restaurant_id:   String
    let user_id:         String
    let total_amount:    Double
    let status:          String
    let cook_time:       Int?
    let take_away:       Bool?
    let schedule_date:   String?
    let order_time:      String?
    let rating:          Int?

    // Joined from `restaurants`
    struct RestaurantJoin: Codable {
        let name: String
        let location: String?
    }
    let restaurants: RestaurantJoin?

    // Joined from `order_items`
    struct OrderItemJoin: Codable {
        let id:         String
        let product_id: String?
        let name:       String
        let quantity:   Int
        let price:      Double
    }
    let order_items: [OrderItemJoin]?

    /// Convert to the existing `UserOrder` model from UserOrdersView.swift.
    ///
    /// UserOrder init:
    ///   init(id: String, restaurantId: String, userID: String,
    ///        items: [UserOrderItem], totalAmount: String, status: String,
    ///        cookTime: Int, takeAway: Bool, time: Date, scheduleDate: Date?,
    ///        restaurantName: String, restaurantLocation: String, rating: Int?)
    func toUserOrder() -> UserOrder {
        // Map order items
        let items = (order_items ?? []).map { item in
            UserOrderItem(
                id:        item.id,
                productId: item.product_id ?? "",
                name:      item.name,
                quantity:  item.quantity,
                price:     item.price
            )
        }

        // Parse order time
        let orderDate = SBOrderRow.parseDate(order_time) ?? Date()

        // Parse schedule date
        let schedDate = schedule_date != nil ? SBOrderRow.parseDate(schedule_date) : nil

        return UserOrder(
            id:                 id,
            restaurantId:       restaurant_id,
            userID:             user_id,
            items:              items,
            totalAmount:        String(format: "%.2f", total_amount),  // Double → String
            status:             status,
            cookTime:           cook_time ?? 0,
            takeAway:           take_away ?? false,
            time:               orderDate,
            scheduleDate:       schedDate,
            restaurantName:     restaurants?.name ?? "Restaurant",
            restaurantLocation: restaurants?.location ?? "Unknown location",
            rating:             rating
        )
    }

    /// Parse ISO8601 date strings from Supabase.
    private static func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }

        // Try ISO8601 with fractional seconds first
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }

        // Fallback without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }

        // Last resort: DateFormatter
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss"] {
            df.dateFormat = fmt
            if let date = df.date(from: string) { return date }
        }

        return nil
    }
}
