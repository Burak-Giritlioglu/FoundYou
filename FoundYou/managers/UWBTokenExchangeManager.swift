import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class UWBTokenExchangeManager: ObservableObject {

    @Published private(set) var peerTokenData: Data?
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private var activeSessionID: String?
    private var generation = 0

    // MARK: - Start Exchange

    func start(
        session: PairingSession,
        myTokenData: Data
    ) {
        guard session.status == .connected else {
            errorMessage = "Eşleştirme henüz onaylanmadı."
            return
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Firebase oturumu bulunamadı."
            return
        }

        let peerUID: String

        if session.hostUID == uid {
            guard let guestUID = session.guestUID else {
                errorMessage = "Arkadaş UID'si bulunamadı."
                return
            }
            peerUID = guestUID
        } else if session.guestUID == uid {
            peerUID = session.hostUID
        } else {
            errorMessage = "Bu eşleştirmenin katılımcısı değilsin."
            return
        }

        stop()

        activeSessionID = session.id
        isListening = true
        errorMessage = nil

        let currentGeneration = generation

        let users = db
            .collection("uwbTokens")
            .document(session.id)
            .collection("users")

        // Listen to the other phone's token.
        listener = users.document(peerUID)
            .addSnapshotListener { [weak self] snapshot, error in

                Task { @MainActor in
                    guard let self,
                          self.isListening,
                          self.generation == currentGeneration,
                          self.activeSessionID == session.id else {
                        return
                    }

                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    guard let tokenString = snapshot?.data()?["token"]
                        as? String,
                          let tokenData = Data(
                            base64Encoded: tokenString
                          ) else {
                        self.peerTokenData = nil
                        return
                    }

                    self.peerTokenData = tokenData
                }
            }

        // Publish our own token.
        let reference = users.document(uid)

        Task { [weak self] in
            guard let self,
                  self.isListening,
                  self.generation == currentGeneration else {
                return
            }

            do {
                try await reference.setData([
                    "token": myTokenData.base64EncodedString(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

            } catch {
                guard self.isListening,
                      self.generation == currentGeneration else {
                    return
                }

                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Stop Exchange

    func stop() {
        generation += 1

        listener?.remove()
        listener = nil

        activeSessionID = nil
        peerTokenData = nil
        isListening = false
        errorMessage = nil
    }

    deinit {
        listener?.remove()
    }
}
