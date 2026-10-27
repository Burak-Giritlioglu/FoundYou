
import Foundation
import Combine
import FirebaseAuth
import FirebaseDatabase

@MainActor
final class UWBTokenExchangeManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var peerTokenData: Data?
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    // MARK: - Database

    private let db = Database.database(
        url: "https://foundyou-5a965-default-rtdb.europe-west1.firebasedatabase.app"
    )

    private var myReference: DatabaseReference?
    private var peerReference: DatabaseReference?
    private var peerObserver: DatabaseHandle?

    // MARK: - State

    private var activeSessionID: String?
    private var generation = 0

    private var desiredToken: Data?
    private var uploadedToken: Data?

    private var writeInProgress = false
    private var cleanupInProgress = false

    private var pendingStart: (PairingSession, Data)?

    // MARK: - Start

    func start(
        session: PairingSession,
        myTokenData: Data
    ) {

        guard session.status == .connected,
              let uid = Auth.auth().currentUser?.uid else {

            errorMessage = "Connection is not ready."
            return
        }

        let otherUID: String

        if session.hostUID == uid {
            guard let guest = session.guestUID else {
                errorMessage = "Friend is missing."
                return
            }
            otherUID = guest

        } else if session.guestUID == uid {
            otherUID = session.hostUID

        } else {
            errorMessage = "You are not part of this connection."
            return
        }

        // Wait for the previous token cleanup
        // before starting a new exchange.

        if cleanupInProgress {
            pendingStart = (session, myTokenData)
            return
        }

        if isListening,
           activeSessionID == session.id {

            guard desiredToken != myTokenData else {
                return
            }

            desiredToken = myTokenData
            publishIfNeeded()
            return
        }

        if isListening {
            pendingStart = (session, myTokenData)
            stop()
            return
        }

        generation += 1
        let currentGeneration = generation

        activeSessionID = session.id
        desiredToken = myTokenData
        uploadedToken = nil

        peerTokenData = nil
        errorMessage = nil
        isListening = true

        let root = db.reference()
            .child("uwbTokens")
            .child(session.id)

        let localReference = root.child(uid)
        let remoteReference = root.child(otherUID)

        myReference = localReference
        peerReference = remoteReference

        // Arrange automatic token removal
        // if Firebase detects a disconnection.

        localReference.onDisconnectRemoveValue {
            [weak self] error, _ in

            Task { @MainActor [weak self] in

                guard let self,
                      self.generation == currentGeneration,
                      self.isListening else {
                    return
                }

                if let error {
                    self.errorMessage =
                        error.localizedDescription

                    self.stop()
                    return
                }

                self.observePeer(
                    remoteReference,
                    generation: currentGeneration
                )

                self.publishIfNeeded()
            }
        }
    }

    // MARK: - Observe Peer Token

    private func observePeer(
        _ reference: DatabaseReference,
        generation currentGeneration: Int
    ) {

        peerObserver = reference.observe(
            .value,
            with: { [weak self] snapshot in

                Task { @MainActor [weak self] in

                    guard let self,
                          self.isListening,
                          self.generation == currentGeneration else {
                        return
                    }

                    guard let data = snapshot.value
                            as? [String: Any],
                          let tokenString = data["token"]
                            as? String,
                          let token = Data(
                            base64Encoded: tokenString
                          ),
                          !token.isEmpty else {

                        self.peerTokenData = nil
                        return
                    }

                    // Ignore unchanged tokens.
                    if self.peerTokenData != token {
                        self.peerTokenData = token
                    }
                }

            },
            withCancel: { [weak self] error in

                Task { @MainActor [weak self] in

                    guard let self,
                          self.generation == currentGeneration else {
                        return
                    }

                    self.errorMessage =
                        error.localizedDescription
                }
            }
        )
    }

    // MARK: - Publish Local Token

    private func publishIfNeeded() {

        guard isListening,
              !writeInProgress,
              !cleanupInProgress,
              let reference = myReference,
              let token = desiredToken,
              token != uploadedToken else {
            return
        }

        writeInProgress = true

        let currentGeneration = generation

        let payload: [String: Any] = [
            "token": token.base64EncodedString(),
            "updatedAt": ServerValue.timestamp()
        ]

        reference.setValue(payload) {
            [weak self] error, _ in

            Task { @MainActor [weak self] in

                guard let self,
                      self.generation == currentGeneration else {
                    return
                }

                self.writeInProgress = false

                guard self.isListening else {
                    return
                }

                if let error {
                    self.errorMessage =
                        error.localizedDescription
                    return
                }

                self.uploadedToken = token
                self.errorMessage = nil

                // Publish once more only if Nearby
                // Interaction generated a newer token.
                self.publishIfNeeded()
            }
        }
    }

    // MARK: - Stop

    func stop() {

        generation += 1

        let referenceToRemove = myReference

        if let reference = peerReference,
           let observer = peerObserver {

            reference.removeObserver(
                withHandle: observer
            )
        }

        peerReference = nil
        peerObserver = nil
        myReference = nil

        activeSessionID = nil

        desiredToken = nil
        uploadedToken = nil

        peerTokenData = nil

        isListening = false
        writeInProgress = false
        errorMessage = nil

        guard let referenceToRemove else {
            resumePendingStart()
            return
        }

        // One cleanup operation when UWB ends.
        // Not a periodic write.

        cleanupInProgress = true

        referenceToRemove.removeValue {
            [weak self] error, _ in

            Task { @MainActor [weak self] in

                guard let self else {
                    return
                }

                self.cleanupInProgress = false

                if let error {
                    self.errorMessage =
                        error.localizedDescription

                    // Keep server-side disconnect
                    // cleanup registered on failure.
                    self.pendingStart = nil
                    return
                }

                referenceToRemove
                    .cancelDisconnectOperations()

                self.resumePendingStart()
            }
        }
    }

    // MARK: - Pending Restart

    private func resumePendingStart() {

        guard !cleanupInProgress,
              let pending = pendingStart else {
            return
        }

        pendingStart = nil

        start(
            session: pending.0,
            myTokenData: pending.1
        )
    }

    // MARK: - Cleanup

    deinit {

        if let reference = peerReference,
           let observer = peerObserver {

            reference.removeObserver(
                withHandle: observer
            )
        }
    }
}
