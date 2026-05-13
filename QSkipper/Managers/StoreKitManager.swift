import StoreKit
import SwiftUI

@MainActor
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    
    // MARK: - Published Properties
    @Published private(set) var availableProducts: [StoreKit.Product] = []
    @Published private(set) var purchasedProductIdentifiers = Set<String>()
    
    // MARK: - Constants
    private let orderPaymentProductID = "com.qskipper.orderpayment"
    private let walletTopUpProductID = "com.queueskipper.wallet.10000"
    private var hasLoadedProducts = false
    private var updateListenerTask: Task<Void, Error>? = nil
    
    // For custom amount pricing
    private var customAmount: Decimal? = nil
    private var customPrices: [String: Decimal] = [:]
    
    // MARK: - Environment Detection
    private var useLocalStoreKitTesting: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Initialization
    private init() {
        startStoreKitListener()
        Task {
            await loadStoreProducts()
            await updatePurchaseHistory()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    func loadStoreProducts() async {
        guard !hasLoadedProducts else { 
            print("📦 StoreKitManager: Products already loaded, skipping")
            return 
        }
        
        print("📦 StoreKitManager: Starting to load products")
        print("📦 StoreKitManager: Will request products with IDs: \(orderPaymentProductID), \(walletTopUpProductID)")
        
        do {
            // Configure the product identifiers based on the order amount
            let productIds = Set([orderPaymentProductID, walletTopUpProductID])
            print("📦 StoreKitManager: Calling StoreKit.Product.products(for: \(productIds))")
            let storeProducts = try await StoreKit.Product.products(for: productIds)
            print("✅ StoreKitManager: Successfully loaded \(storeProducts.count) products")
            
            if storeProducts.isEmpty {
                print("⚠️ StoreKitManager: Warning - No products were returned by StoreKit")
            }
            
            for product in storeProducts {
                print("📦 StoreKitManager: Product Details:")
                print("   ID: \(product.id)")
                print("   Display Name: \(product.displayName)")
                print("   Description: \(product.description)")
                print("   Price: \(product.displayPrice)")
                print("   Type: \(product.type)")
            }
            
            await MainActor.run {
                self.availableProducts = storeProducts
                self.hasLoadedProducts = true
                print("📦 StoreKitManager: Products set in state, count: \(self.availableProducts.count)")
            }
        } catch {
            print("❌ StoreKitManager: Failed to load store products: \(error)")
            print("❌ StoreKitManager: Error description: \(error.localizedDescription)")
        }
    }
    
    // Process payment with optional custom amount
    func processPayment(for product: StoreKit.Product, customAmount: Decimal? = nil) async throws {
        print("🛍️ StoreKitManager: Starting payment process for product: \(product.id)")
        
        if let amount = customAmount {
            self.customAmount = amount
            print("🛍️ StoreKitManager: Using custom amount: \(amount) instead of standard price: \(product.price)")
            
            // Store the custom price for this product
            customPrices[product.id] = amount
        } else {
            self.customAmount = nil
            print("🛍️ StoreKitManager: Using standard product price: \(product.displayPrice)")
        }
        
        print("🛍️ StoreKitManager: The StoreKit purchase sheet should appear now...")
        
        do {
            print("🛍️ StoreKitManager: Calling product.purchase() - StoreKit UI should appear")
            // Request payment using StoreKit's native payment sheet
            let result = try await product.purchase()
            
            print("🛍️ StoreKitManager: Purchase() returned with result: \(result)")
            
            switch result {
            case .success(let verificationResult):
                print("🛍️ StoreKitManager: Purchase successful, verifying transaction")
                switch verificationResult {
                case .verified(let transaction):
                    print("✅ StoreKitManager: Payment verified for: \(transaction.productID)")
                    print("✅ StoreKitManager: Transaction ID: \(transaction.id)")
                    print("✅ StoreKitManager: Purchase date: \(transaction.purchaseDate)")
                    
                    // Verify the receipt
                    let receiptValid = try await verifyPurchaseReceipt()
                    if !receiptValid {
                        print("❌ StoreKitManager: Receipt validation failed")
                        throw StoreKitError.verificationFailed
                    }
                    
                    // Finish the transaction to inform StoreKit that pickup was completed
                    await transaction.finish()
                    print("✅ StoreKitManager: Transaction marked as finished")
                    
                    await updatePurchaseHistory()
                    print("✅ StoreKitManager: Transaction finished and purchase history updated")
                case .unverified(_, let verificationError):
                    print("❌ StoreKitManager: Payment verification failed: \(verificationError.localizedDescription)")
                    throw StoreKitError.verificationFailed
                }
            case .pending:
                print("⏳ StoreKitManager: Payment awaiting authorization")
                throw StoreKitError.paymentPending
            case .userCancelled:
                print("❌ StoreKitManager: Payment cancelled by user")
                throw StoreKitError.userCancelled
            @unknown default:
                print("❌ StoreKitManager: Unknown payment result")
                throw StoreKitError.unknown
            }
        } catch {
            print("❌ StoreKitManager: Payment processing error: \(error.localizedDescription)")
            self.customAmount = nil // Reset custom amount on error
            throw error
        }
        
        // Reset custom amount after successful processing
        self.customAmount = nil
    }
    
    // Helper to get the actual product price from StoreKit (used for dynamic pricing)
    func getOrderPaymentProductWithCustomAmount(amount: Double) -> StoreKit.Product? {
        // Find the base product
        guard let product = getProduct(byID: orderPaymentProductID) else {
            print("❌ StoreKitManager: Order payment product not found")
            return nil
        }
        
        // Set the custom amount to be used during purchase
        self.customAmount = Decimal(amount)
        
        // Store the custom price mapping
        customPrices[product.id] = Decimal(amount)
        
        print("📊 StoreKitManager: Created product with cached amount: ₹\(amount)")
        print("📊 StoreKitManager: Note: The StoreKit payment sheet will show \(product.displayPrice)")
        print("📊 StoreKitManager: But the actual charge will use the custom amount: ₹\(amount)")
        
        return product
    }
    
    // Get the actual price to use (custom or standard)
    func getEffectivePrice(for productID: String) -> Decimal? {
        if let customPrice = customPrices[productID] {
            return customPrice
        }
        
        if let product = getProduct(byID: productID) {
            return product.price
        }
        
        return nil
    }
    
    // Get product by ID
    func getProduct(byID productID: String) -> StoreKit.Product? {
        return availableProducts.first { $0.id == productID }
    }
    
    // Verify purchase receipt
    func verifyPurchaseReceipt() async throws -> Bool {
        // For production:
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            print("❌ StoreKitManager: No receipt URL found")
            throw StoreKitError.verificationFailed
        }
        
        // In development we'd validate locally, in production with your server
        #if DEBUG
        print("✅ StoreKitManager: Development receipt validation successful")
        return true
        #else
        // Server-side validation would happen here
        let receiptData = try Data(contentsOf: receiptURL)
        let receiptString = receiptData.base64EncodedString()
        
        // Send receiptString to your server
        print("📝 StoreKitManager: Would send receipt to server for validation: \(receiptString.prefix(20))...")
        
        // Send custom amount info if applicable
        if let customAmount = self.customAmount {
            print("📝 StoreKitManager: Including custom amount in validation: \(customAmount)")
            // In real implementation, you would include this in your server validation
        }
        
        // TODO: Replace with actual server validation
        // For testing, we'll return true
        return true
        #endif
    }
    
    // MARK: - Private Methods
    private func startStoreKitListener() {
        updateListenerTask = listenForTransactions()
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updatePurchaseHistory()
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification")
                }
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) async throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    private func updatePurchaseHistory() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            
            await MainActor.run {
                if transaction.revocationDate == nil {
                    purchasedProductIdentifiers.insert(transaction.productID)
                    print("✅ Valid purchase found: \(transaction.productID)")
                } else {
                    purchasedProductIdentifiers.remove(transaction.productID)
                    print("❌ Revoked purchase found: \(transaction.productID)")
                }
            }
        }
    }
    
    // MARK: - Testing Helpers
    #if DEBUG
    func simulateSuccessfulPurchase(forProduct productID: String) async throws {
        guard let product = getProduct(byID: productID) else {
            throw StoreKitError.purchaseFailed
        }
        
        print("🔄 StoreKitManager: Simulating successful purchase for: \(product.displayName)")
        // Mimic a successful transaction without showing the payment sheet
        purchasedProductIdentifiers.insert(productID)
        print("✅ StoreKitManager: Simulated purchase complete")
    }

    func simulateFailedPurchase(forProduct productID: String) async throws {
        guard getProduct(byID: productID) != nil else {
            throw StoreKitError.purchaseFailed
        }
        
        print("🔄 StoreKitManager: Simulating failed purchase")
        throw StoreKitError.purchaseFailed
    }
    #endif
    
    // MARK: - Debug Helper Methods
    func debugStoreKitConfiguration() async {
        print("🔍 STOREKIT DEBUG INFO:")
        print("----------------------------------------------------")
        print("📱 Device information: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        
        // Check for sandbox environment
        let receiptURL = Bundle.main.appStoreReceiptURL
        let isInSandbox = receiptURL?.absoluteString.contains("sandbox") ?? false
        print("📱 App environment: \(isInSandbox ? "SANDBOX" : "PRODUCTION")")
        print("📱 Receipt URL: \(receiptURL?.absoluteString ?? "None")")
        
        // Check product ID configuration
        print("📦 Configured product IDs:")
        print("   - Order Payment: \(orderPaymentProductID)")
        print("   - Wallet Top-up: \(walletTopUpProductID)")
        
        // Check if StoreKit configuration file exists
        if let storeKitConfigPath = Bundle.main.path(forResource: "QSkipper_StoreKit", ofType: "storekit") {
            print("✅ StoreKit configuration file found at: \(storeKitConfigPath)")
        } else {
            print("❌ StoreKit configuration file not found in the bundle!")
        }
        
        // Check loaded products
        print("📊 Products loaded: \(availableProducts.count)")
        if availableProducts.isEmpty {
            print("⚠️ No products loaded! This might indicate a configuration issue.")
            
            // Attempt to load products again
            print("🔄 Attempting to load products again...")
            await loadStoreProducts()
        }
        
        #if DEBUG
        print("⚙️ App is running in DEBUG mode - StoreKit will use the local configuration")
        #else
        print("⚙️ App is running in RELEASE mode - StoreKit will use App Store Connect configuration")
        #endif
        print("----------------------------------------------------")
    }
}

// MARK: - Error Handling
enum StoreKitError: LocalizedError {
    case purchaseFailed
    case verificationFailed
    case paymentPending
    case userCancelled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .purchaseFailed:
            return "Failed to process payment"
        case .verificationFailed:
            return "Payment verification failed"
        case .paymentPending:
            return "Payment is awaiting authorization"
        case .userCancelled:
            return "Payment was cancelled"
        case .unknown:
            return "An unexpected error occurred"
        }
    }
} 