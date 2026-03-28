import SwiftUI

struct SplashScreenView: View {
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                if let icon = UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .cornerRadius(24)
                        .shadow(color: .white.opacity(0.1), radius: 10, x: 0, y: 0)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                Text("DualCast")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(2)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                    .padding(.top, 10)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }
            }
        }
    }
}
