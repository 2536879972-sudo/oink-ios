import SwiftUI

@main
struct AishijieApp: App {
    @StateObject private var store = ChatStore()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ChatView()
                    .environmentObject(store)
                    .preferredColorScheme(nil)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
