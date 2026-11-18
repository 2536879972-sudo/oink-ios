import SwiftUI

@main
struct OinkApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(store)
                .preferredColorScheme(nil)
        }
    }
}
