//
//  SupabaseRestaurantService.swift
//  QSkipper
//
//  Fetches restaurants, products, and top picks from Supabase.
//  Returns the EXISTING Restaurant / Product model types so all Views work unchanged.
//
//  This file is ADDITIVE — it does NOT replace NetworkUtils.swift or RestaurantManager.swift.
//

import Foundation
import Supabase

class SupabaseRestaurantService {

    static let shared = SupabaseRestaurantService()

    private init() {}

    // MARK: - Restaurants (replaces GET /get_All_Restaurant)

    /// Fetch all active restaurants from Supabase.
    /// Returns the existing `Restaurant` model used throughout the app.
    func fetchAllRestaurants() async throws -> [Restaurant] {
        let rows: [SBRestaurantRow] = try await supabaseClient
            .from("restaurants")
            .select("*")
            .eq("is_active", value: true)
            .order("name")
            .execute()
            .value

        print("✅ SupabaseRestaurantService: Fetched \(rows.count) restaurants")
        return rows.map { $0.toRestaurant() }
    }

    /// Fetch a single restaurant by ID.
    func fetchRestaurant(id: String) async throws -> Restaurant {
        let row: SBRestaurantRow = try await supabaseClient
            .from("restaurants")
            .select("*")
            .eq("id", value: id)
            .single()
            .execute()
            .value

        print("✅ SupabaseRestaurantService: Fetched restaurant \(row.name)")
        return row.toRestaurant()
    }

    // MARK: - Products (replaces GET /get_All_Products/:id)

    /// Fetch all active products for a restaurant.
    /// Returns the existing `Product` model used throughout the app.
    func fetchProducts(for restaurantId: String) async throws -> [Product] {
        let rows: [SBProductRow] = try await supabaseClient
            .from("products")
            .select("*")
            .eq("restaurant_id", value: restaurantId)
            .eq("is_active", value: true)
            .order("category")
            .execute()
            .value

        print("✅ SupabaseRestaurantService: Fetched \(rows.count) products for restaurant \(restaurantId)")
        return rows.map { $0.toProduct() }
    }

    // MARK: - Top Picks (replaces GET /top-picks)

    /// Fetch top-pick products across all restaurants.
    func fetchTopPicks() async throws -> [Product] {
        let rows: [SBProductRow] = try await supabaseClient
            .from("products")
            .select("*")
            .eq("top_picks", value: true)
            .eq("is_available", value: true)
            .eq("is_active", value: true)
            .order("rating", ascending: false)
            .limit(20)
            .execute()
            .value

        print("✅ SupabaseRestaurantService: Fetched \(rows.count) top picks")
        return rows.map { $0.toProduct() }
    }

    // MARK: - Image URLs (replaces /get_restaurant_photo/:id and /get_product_photo/:id)

    /// Public URL for a restaurant image in Supabase Storage.
    func restaurantImageURL(photoId: String) -> URL? {
        try? supabaseClient.storage
            .from("restaurant-images")
            .getPublicURL(path: "\(photoId).jpg")
    }

    /// Public URL for a product image in Supabase Storage.
    func productImageURL(photoId: String) -> URL? {
        try? supabaseClient.storage
            .from("product-images")
            .getPublicURL(path: "\(photoId).jpg")
    }
}


// ============================================================
// MARK: - Codable Row Structs (internal, maps Supabase → existing models)
// ============================================================

/// Matches the `restaurants` table columns in Supabase (snake_case).
private struct SBRestaurantRow: Codable {
    let id:               String
    let name:             String
    let cuisine:          String?
    let estimated_time:   Int?
    let photo_id:         String?
    let rating:           Double?
    let location:         String?
    let is_active:        Bool?

    // Optional columns from admin schema that may exist
    let banner_image_url: String?
    let owner_id:         String?

    // Provide defaults for optional columns that might not exist
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id              = try container.decode(String.self, forKey: .id)
        name            = try container.decode(String.self, forKey: .name)
        cuisine         = try? container.decode(String.self, forKey: .cuisine)
        estimated_time  = try? container.decode(Int.self, forKey: .estimated_time)
        photo_id        = try? container.decode(String.self, forKey: .photo_id)
        rating          = try? container.decode(Double.self, forKey: .rating)
        location        = try? container.decode(String.self, forKey: .location)
        is_active       = try? container.decode(Bool.self, forKey: .is_active)
        banner_image_url = try? container.decode(String.self, forKey: .banner_image_url)
        owner_id        = try? container.decode(String.self, forKey: .owner_id)
    }

    /// Convert to the existing `Restaurant` model that all Views use.
    ///
    /// Restaurant init signature (from RestaurantModels.swift):
    ///   init(id: String, name: String, estimatedTime: String?,
    ///        cuisine: String?, photoId: String?, rating: Double, location: String)
    func toRestaurant() -> Restaurant {
        // Prefer the full Supabase Storage URL stored in banner_image_url,
        // fall back to photo_id (UUID), then restaurant id
        let effectivePhotoId = banner_image_url ?? photo_id ?? id
        return Restaurant(
            id:            id,
            name:          name,
            estimatedTime: estimated_time != nil ? String(estimated_time!) : "30-40",
            cuisine:       cuisine ?? "Various",
            photoId:       effectivePhotoId,
            rating:        rating ?? 4.0,
            location:      location ?? "🏫 Campus Cafeteria"
        )
    }
}

/// Matches the `products` table columns in Supabase (snake_case).
private struct SBProductRow: Codable {
    let id:             String
    let restaurant_id:  String
    let name:           String
    let price:          Double
    let category:       String?
    let description:    String?
    let extra_time:     Int?
    let rating:         Double?
    let is_available:   Bool?
    let is_active:      Bool?
    let image_url:      String?
    let photo_id:       String?
    let is_veg:         Bool?
    let top_picks:      Bool?
    let quantity:       Int?

    // Provide defaults for optional columns
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id             = try container.decode(String.self, forKey: .id)
        restaurant_id  = try container.decode(String.self, forKey: .restaurant_id)
        name           = try container.decode(String.self, forKey: .name)
        price          = try container.decode(Double.self, forKey: .price)
        category       = try? container.decode(String.self, forKey: .category)
        description    = try? container.decode(String.self, forKey: .description)
        extra_time     = try? container.decode(Int.self, forKey: .extra_time)
        rating         = try? container.decode(Double.self, forKey: .rating)
        is_available   = try? container.decode(Bool.self, forKey: .is_available)
        is_active      = try? container.decode(Bool.self, forKey: .is_active)
        image_url      = try? container.decode(String.self, forKey: .image_url)
        photo_id       = try? container.decode(String.self, forKey: .photo_id)
        is_veg         = try? container.decode(Bool.self, forKey: .is_veg)
        top_picks      = try? container.decode(Bool.self, forKey: .top_picks)
        quantity       = try? container.decode(Int.self, forKey: .quantity)
    }

    /// Convert to the existing `Product` model that all Views use.
    ///
    /// Product init signature (from RestaurantModels.swift):
    ///   init(id: String, name: String, description: String?, price: Double,
    ///        restaurantId: String, category: String?, isAvailable: Bool,
    ///        rating: Double, extraTime: Int?, photoId: String?, isVeg: Bool)
    func toProduct() -> Product {
        // Prefer the full Supabase Storage URL stored in image_url,
        // fall back to photo_id (UUID), then product id
        let effectivePhotoId = image_url ?? photo_id ?? id
        return Product(
            id:           id,
            name:         name,
            description:  description,
            price:        price,
            restaurantId: restaurant_id,
            category:     category,
            isAvailable:  is_available ?? true,
            rating:       rating ?? 4.0,
            extraTime:    extra_time,
            photoId:      effectivePhotoId,
            isVeg:        is_veg ?? true
        )
    }
}
