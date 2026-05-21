//
//  UserOrdersView.swift
//  QSkipper
//
//  Created by Keshav Lohiya on 01/04/25.
//

import SwiftUI
import Foundation

struct UserOrdersView: View {
    @StateObject private var viewModel = UserOrdersViewModel()
    @State private var searchText = ""
    @EnvironmentObject private var tabSelection: TabSelection
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Spacer()
                        
                        Text("Your Orders")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColors.darkGray)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search by restaurant or dish", text: $searchText)
                            .font(.system(size: 16))
                            .focused($isSearchFieldFocused)
                            .onChange(of: isSearchFieldFocused) { oldValue, newValue in
                                isSearching = newValue
                            }
                        
                        // Cancel button appears when searching
                        if isSearching {
                            Button {
                                searchText = ""
                                isSearchFieldFocused = false
                            } label: {
                                Text("Cancel")
                                    .foregroundColor(AppColors.primaryGreen)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(30)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView("Loading orders...")
                        Spacer()
                    } else if viewModel.orders.isEmpty {
                        EmptyOrdersView(onRetry: {
                            viewModel.fetchOrders()
                        }, lastRefreshTime: viewModel.lastRefreshTime)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.filteredOrders(searchText: searchText)) { order in
                                    OrderCard(order: order)
                                        .padding(.horizontal, 16)
                                }
                                
                                // Add extra space at the bottom to ensure the last order is fully visible
                                Color.clear
                                    .frame(height: 120)
                            }
                            .padding(.vertical, 8)
                        }
                        .refreshable {
                            // Pull to refresh functionality
                            print("🔄 Pull-to-refresh triggered")
                            viewModel.fetchOrders()
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded { _ in
                                if isSearchFieldFocused {
                                    isSearchFieldFocused = false
                                }
                            }
                        )
                    }
                }
                .onTapGesture {
                    // Dismiss keyboard when tapping outside search field
                    if isSearchFieldFocused {
                        isSearchFieldFocused = false
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                viewModel.fetchOrders()
            }
            .onChange(of: tabSelection.selectedTab) { oldValue, newTab in
                if newTab == .orders {
                    print("📱 Orders tab selected, refreshing data")
                    viewModel.fetchOrders()
                }
            }
            .overlay(
                Group {
                    if let errorMessage = viewModel.errorMessage {
                        VStack {
                            Spacer()
                            
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                
                                Text(errorMessage)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Button {
                                    viewModel.errorMessage = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding()
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                            .padding()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut, value: viewModel.errorMessage != nil)
                    }
                }
            )
        }
    }
}

struct EmptyOrdersView: View {
    var onRetry: (() -> Void)? = nil
    var lastRefreshTime: Date? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bag")
                .font(.system(size: 60))
                .foregroundColor(AppColors.primaryGreen.opacity(0.4))
            
            Text("No orders yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.darkGray)
            
            Text("Your past orders will appear here")
                .font(.system(size: 14))
                .foregroundColor(AppColors.mediumGray)
                .multilineTextAlignment(.center)
            
            // Last updated timestamp removed
            
            if let retry = onRetry {
                Button(action: retry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppColors.primaryGreen)
                    .cornerRadius(8)
                }
                .padding(.top, 10)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // Convert date to "3 minutes ago" format
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.second, .minute, .hour, .day], from: date, to: now)
        
        if let day = components.day, day > 0 {
            return "\(day) day\(day == 1 ? "" : "s") ago"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour) hour\(hour == 1 ? "" : "s") ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute) minute\(minute == 1 ? "" : "s") ago"
        } else {
            return "just now"
        }
    }
}

struct OrderCard: View {
    var order: UserOrder
    @State private var isDelivering = false
    @EnvironmentObject private var tabSelection: TabSelection
    @State private var isReordering = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showRatingSheet = false
    @State private var selectedRating: Int = 0
    @State private var isSubmittingRating = false
    @State private var localRating: Int? = nil
    var onRatingSubmitted: ((String, Int) -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Restaurant info
            HStack {
                // Restaurant image
                RestaurantImageLoader(restaurantId: order.restaurantId)
                    .frame(width: 48, height: 48)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.restaurantName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.darkGray)
                    
                    Text(order.restaurantLocation)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    // Menu options
                } label: {
                    Image(systemName: "ellipsis.vertical")
                        .foregroundColor(.gray)
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Order items
            VStack(alignment: .leading, spacing: 8) {
                ForEach(order.items) { item in
                    HStack(spacing: 10) {
                        // Green checkmark or bullet
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        
                        Text("\(item.quantity) × \(item.name)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.darkGray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Order details
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    
                    Text("₹\(order.totalAmount)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.primaryGreen)
                }
                
                // Add scheduled date display if available
                if let scheduleDate = order.scheduleDate {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(AppColors.primaryGreen)
                            .font(.system(size: 16))
                        
                        Text("Scheduled on: \(formattedDate(scheduleDate))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.primaryGreen)
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(AppColors.primaryGreen.opacity(0.1))
                    .cornerRadius(8)
                }
                
                HStack {
                    // Order status with icon - removing emoji/icon as requested
                    Text(getOrderStatusText(for: order.status))
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    // Delivery status button
                    if !isCurrentlyDelivering(order: order) {
                        if order.status.lowercased() == "placed" {
                            Button {
                                // Action for "Preparing" status
                            } label: {
                                Text("Preparing")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppColors.primaryGreen)
                                    .cornerRadius(16)
                            }
                        } else if order.status.lowercased() == "completed" {
                            Button {
                                // Add the items from this order to the cart
                                isReordering = true
                                reorderItems()
                            } label: {
                                if isReordering {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: 24, height: 24)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppColors.primaryGreen)
                                        .cornerRadius(16)
                                } else {
                                    Text("Reorder")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppColors.primaryGreen)
                                        .cornerRadius(16)
                                }
                            }
                            .disabled(isReordering)
                            
                            // Rate button for completed & unrated orders
                            if (localRating ?? order.rating) == nil {
                                Button {
                                    selectedRating = 0
                                    showRatingSheet = true
                                } label: {
                                    Text("Rate")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppColors.primaryGreen)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppColors.primaryGreen.opacity(0.1))
                                        .cornerRadius(16)
                                }
                            }
                        } else {
                            Button {
                                // No action - just a status indicator
                            } label: {
                                Text(order.scheduleDate != nil ? "Scheduled" : "")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(order.scheduleDate != nil ? AppColors.primaryGreen.opacity(0.1) : Color.gray.opacity(0.2))
                                    .cornerRadius(16)
                            }
                            .disabled(true)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if let rating = localRating ?? order.rating, rating > 0 {
                Divider()
                
                // Rating section if available
                HStack {
                    Text("You rated \(rating)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.system(size: 12))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .sheet(isPresented: $showRatingSheet) {
            ratingSheetView
                .presentationDetents([.height(300)])
        }
        .overlay(
            // Toast notification
            VStack {
                if showToast {
                    Text(toastMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppColors.primaryGreen)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            // Automatically hide toast after 3 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    showToast = false
                                }
                            }
                        }
                }
            }
            .padding(.top, 5)
            .animation(.easeInOut(duration: 0.3), value: showToast)
            .zIndex(1)
        )
        .onAppear {
            // Log debugging information for scheduled dates
            print("🔍 Checking scheduleDate for order \(order.id): \(order.scheduleDate != nil ? "Available" : "Not available")")
            if let scheduleDate = order.scheduleDate {
                print("📆 Found scheduleDate: \(scheduleDate)")
            } else {
                print("⚠️ No scheduleDate found for order \(order.id)")
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        let result = formatter.string(from: date)
        print("🔶 Formatted date result: \(result)")
        return result
    }
    
    private func getOrderStatusIcon(for status: String) -> String {
        switch status.lowercased() {
        case "pending":
            return "clock"
        case "preparing":
            return "flame"
        case "ready", "ready_for_pickup":
            return "checkmark.circle"
        case "completed":
            return "bag.fill"
        case "cancelled":
            return "xmark.circle"
        default:
            return order.takeAway ? "" : "takeoutbag.and.cup.and.straw.fill"
        }
    }
    
    private func getOrderStatusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "pending":
            return .orange
        case "preparing":
            return .blue
        case "ready", "ready_for_pickup":
            return .green
        case "completed":
            return AppColors.primaryGreen
        case "cancelled":
            return .red
        default:
            return order.takeAway ? .orange : .blue
        }
    }
    
    private func getOrderStatusText(for status: String) -> String {
        switch status.lowercased() {
        case "pending":
            return "Pending"
        case "preparing":
            return "Preparing"
        case "placed":
            return "Placed"
        case "schedule":
            return "Scheduled"
        case "ready", "ready_for_pickup":
            return "Ready for pickup"
        case "completed":
            return "Completed"
        case "cancelled":
            return "Cancelled"
        default:
            return "Processing"
        }
    }
    
    private func isCurrentlyDelivering(order: UserOrder) -> Bool {
        // In a real app, this would check if the order is currently out for pickup
        // For now, we'll just return false
        return false
    }
    
    // MARK: - Rating Sheet View
    private var ratingSheetView: some View {
        VStack(spacing: 16) {
            Text("Rate your order")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppColors.darkGray)
                .padding(.top, 20)
            
            // Restaurant name + ordered items
            VStack(spacing: 6) {
                Text(order.restaurantName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.darkGray)
                
                ForEach(order.items) { item in
                    Text("\(item.quantity) × \(item.name)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            
            // Star picker
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= selectedRating ? "star.fill" : "star")
                        .font(.system(size: 36))
                        .foregroundColor(star <= selectedRating ? .yellow : .gray.opacity(0.4))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedRating = star
                            }
                        }
                }
            }
            .padding(.vertical, 10)
            
            // Submit button
            Button {
                guard selectedRating > 0 else { return }
                isSubmittingRating = true
                Task {
                    do {
                        try await SupabaseOrderService.shared.submitRating(orderId: order.id, rating: selectedRating)
                        await MainActor.run {
                            localRating = selectedRating
                            onRatingSubmitted?(order.id, selectedRating)
                            isSubmittingRating = false
                            showRatingSheet = false
                            toastMessage = "Thanks for your rating!"
                            withAnimation { showToast = true }
                        }
                    } catch {
                        await MainActor.run {
                            isSubmittingRating = false
                            toastMessage = "Failed to submit rating"
                            withAnimation { showToast = true }
                        }
                        print("❌ Rating submission failed: \(error.localizedDescription)")
                    }
                }
            } label: {
                if isSubmittingRating {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.primaryGreen)
                        .cornerRadius(12)
                } else {
                    Text("Submit Rating")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedRating > 0 ? AppColors.primaryGreen : Color.gray.opacity(0.4))
                        .cornerRadius(12)
                }
            }
            .disabled(selectedRating == 0 || isSubmittingRating)
            .padding(.horizontal, 30)
            
            Spacer()
        }
    }
    
    // Reorder functionality
    private func reorderItems() {
        // Clear existing cart items first
        OrderManager.shared.clearCart()
        
        // For each item in the order, try to find the product and add it to cart
        Task {
            do {
                // Fetch all products for this restaurant using the correct backend
                let products: [Product]
                if AuthManager.useSupabase {
                    products = try await SupabaseRestaurantService.shared.fetchProducts(for: order.restaurantId)
                } else {
                    products = try await NetworkUtils.shared.fetchProducts(for: order.restaurantId)
                }
                
                // Process each order item
                for item in order.items {
                    // Find the matching product
                    if let product = products.first(where: { $0.id == item.productId }) {
                        // Add the product to the cart with the same quantity
                        DispatchQueue.main.async {
                            OrderManager.shared.addToCart(product: product, quantity: item.quantity)
                            print("✅ Added \(item.quantity) x \(product.name) to cart")
                        }
                    } else {
                        // If we can't find the product, create a simpler version to maintain the order
                        print("⚠️ Product \(item.productId) not found in restaurant products")
                        
                        // This is just for the UI, the actual order will require proper product details
                        let fallbackProduct = Product(
                            id: item.productId,
                            name: item.name,
                            description: "Reordered item",
                            price: item.price,
                            restaurantId: order.restaurantId,
                            category: "Reordered",
                            isAvailable: true,
                            rating: 5.0,
                            extraTime: nil,
                            photoId: nil,
                            isVeg: true
                        )
                        
                        DispatchQueue.main.async {
                            OrderManager.shared.addToCart(product: fallbackProduct, quantity: item.quantity)
                            print("✅ Added fallback \(item.quantity) x \(item.name) to cart")
                        }
                    }
                }
                
                // When finished adding all items, navigate to cart
                DispatchQueue.main.async {
                    self.isReordering = false
                    // Navigate to home tab first
                    self.tabSelection.selectedTab = .home
                    
                    // Show toast notification
                    self.toastMessage = "Items added to cart! Tap the cart icon to checkout."
                    withAnimation {
                        self.showToast = true
                    }
                    
                    // Show a toast or alert to indicate items were added to cart
                    print("✅ All items added to cart! User should tap the cart icon on the home screen.")
                }
                
            } catch {
                print("❌ Error fetching products for reorder: \(error)")
                DispatchQueue.main.async {
                    self.isReordering = false
                }
            }
        }
    }
}

// MARK: - Data Models for User Orders
struct UserOrderItem: Identifiable {
    let id: String
    let productId: String
    let name: String
    let quantity: Int
    let price: Double
}

struct UserOrder: Identifiable {
    let id: String
    let restaurantId: String
    let userID: String
    let items: [UserOrderItem]
    let totalAmount: String
    let status: String
    let cookTime: Int
    let takeAway: Bool
    let time: Date
    let scheduleDate: Date?
    var restaurantName: String
    var restaurantLocation: String
    var rating: Int?
}

#Preview {
    UserOrdersView()
        .environmentObject(TabSelection())
} 
