
import SwiftUI
import FirebaseCore

@main
struct FoundYouApp: App {

    @StateObject private var auth = AuthManager()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .task {
                    await auth.signInAnonymously()
                }
        }
    }
}
