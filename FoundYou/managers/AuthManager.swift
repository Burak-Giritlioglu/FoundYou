import Foundation
import Combine
import FirebaseAuth

@MainActor
final class AuthManager: ObservableObject {

    @Published private(set) var userID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    init() {
        userID = Auth.auth().currentUser?.uid
    }

    func signInAnonymously() async {
        guard !isLoading else { return }

        if let user = Auth.auth().currentUser {
            userID = user.uid
            return
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            userID = result.user.uid
            print("FoundYou Firebase UID:", result.user.uid)
        } catch {
            errorMessage = error.localizedDescription
            print("Firebase Auth error:", error)
        }
    }
}
