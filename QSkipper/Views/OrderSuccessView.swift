import SwiftUI

struct OrderSuccessView: View {
    @ObservedObject var cartManager: OrderManager
    @EnvironmentObject private var tabSelection: TabSelection
    @Environment(\.presentationMode) var presentationMode
    var orderId: String? = nil
    var onDismiss: (() -> Void)? = nil
    @State private var dotOpacity: Double = 0.3
    
    var body: some View {
        ZStack {
            // Splash background
            Image("splash_background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                // Center content
                VStack(spacing: 24) {
                    // Success icon in circle
                    Circle()
                        .fill(AppColors.primaryGreen)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "checkmark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.white)
                        )
                    
                    // Success text
                    Text("Congrats")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(AppColors.primaryGreen)
                    
                    Text("Order placed successfully!")
                        .font(.system(size: 18))
                        .multilineTextAlignment(.center)
                    
                    // Vendor acceptance status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .opacity(dotOpacity)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: dotOpacity
                            )
                        
                        Text("Waiting for vendor's acceptance")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .onAppear {
                        dotOpacity = 1.0
                    }
                }
                
                Spacer()
            }
            
            // Dismiss button — top-right corner (HIG standard)
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        tabSelection.selectedTab = .home
                        if let onDismiss = onDismiss {
                            onDismiss()
                        } else {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                Color.white.opacity(0.9),
                                Color.black.opacity(0.25)
                            )
                    }
                    .padding(.top, 54)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Clear cart if not already cleared
            cartManager.clearCart()
        }
    }
}

#Preview {
    OrderSuccessView(
        cartManager: OrderManager.shared,
        orderId: "67ed11db351a70ac8b9d54af"
    )
    .environmentObject(TabSelection.shared)
} 
