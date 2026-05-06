import SwiftUI

struct OrderSuccessView: View {
    @ObservedObject var cartManager: OrderManager
    @EnvironmentObject private var tabSelection: TabSelection
    @Environment(\.presentationMode) var presentationMode
    var orderId: String? = nil
    
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
