
import Foundation
import Combine
import FirebaseAuth
import FirebaseDatabase

@MainActor
final class FindingStateManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var isFinding = false
    @Published private(set) var isPeerFinding = false
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    // MARK: - Firebase

    private let db = Database.database(
        url: "https://foundyou-5a965-default-rtdb.europe-west1.firebasedatabase.app"
    )

    private var myReference: DatabaseReference?
    private var peerReference: DatabaseReference?
    private var peerObserver: DatabaseHandle?

    // MARK: - State

    private enum Phase {
        case idle
        case registering
        case publishing
        case active
        case removing
    }

    private var phase: Phase = .idle

    private var activeSessionID: String?
    private var generation = 0
    private var wantsToFind = false

    // MARK: - Connect

    func connect(session: PairingSession) {

        guard session.status == .connected,
              let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Connection is not ready."
            return
        }

        let otherUID: String

        if session.hostUID == uid {

            guard let guestUID = session.guestUID else {
                errorMessage = "Friend is missing."
                return
            }

            otherUID = guestUID

        } else if session.guestUID == uid {

            otherUID = session.hostUID

        } else {

            errorMessage = "You are not part of this connection."
            return
        }

        if isConnected && activeSessionID == session.id {
            return
        }

        disconnect()

        activeSessionID = session.id
        isConnected = true
        errorMessage = nil

        let currentGeneration = generation

        let root = db.reference()
            .child("finding")
            .child(session.id)

        myReference = root.child(uid)

        let reference = root.child(otherUID)
        peerReference = reference

        // Only listen to the other person's
        // finding flag. No polling or writes.

        peerObserver = reference.observe(
            .value,
            with: { [weak self] snapshot in

                Task { @MainActor [weak self] in

                    guard let self,
                          self.isConnected,
                          self.generation == currentGeneration else {
                        return
                    }

                    let peerFinding =
                        snapshot.value as? Bool ?? false

                    if self.isPeerFinding != peerFinding {
                        self.isPeerFinding = peerFinding
                    }
                }
            },
            withCancel: { [weak self] error in

                Task { @MainActor [weak self] in

                    guard let self,
                          self.generation == currentGeneration else {
                        return
                    }

                    self.isPeerFinding = false
                    self.errorMessage =
                        error.localizedDescription
                }
            }
        )
    }

    // MARK: - Start Finding

    func startFinding() {

        guard isConnected,
              myReference != nil else {
            return
        }

        // Already requested or active.
        guard !wantsToFind else {
            return
        }

        wantsToFind = true
        errorMessage = nil

        advance()
    }

    // MARK: - Stop Finding

    func stopFinding() {

        guard isConnected else {
            return
        }

        // Change the desired state immediately.
        // If a write is in progress, its callback
        // will perform the cleanup afterward.

        wantsToFind = false
        isFinding = false

        advance()
    }

    // MARK: - State Machine

    private func advance() {

        guard isConnected,
              let reference = myReference else {
            return
        }

        switch phase {

        case .idle:

            if wantsToFind {
                registerDisconnectCleanup(
                    reference: reference
                )
            } else {
                isUpdating = false
            }

        case .registering:

            // Wait for registration to finish.
            // Its callback checks wantsToFind.
            break

        case .publishing:

            // Wait for the true write to finish.
            // Its callback removes stale true
            // if the user has stopped.
            break

        case .active:

            if !wantsToFind {
                removeFindingFlag(
                    reference: reference,
                    requestGeneration: generation
                )
            }

        case .removing:

            // Never publish a new true until
            // the previous removal completes.
            break
        }
    }

    // MARK: - Prepare Disconnect Cleanup

    private func registerDisconnectCleanup(
        reference: DatabaseReference
    ) {

        phase = .registering
        isUpdating = true

        let requestGeneration = generation

        reference.onDisconnectRemoveValue {
            [weak self] error, _ in

            Task { @MainActor [weak self] in

                guard let self else {
                    reference.cancelDisconnectOperations()
                    return
                }

                guard self.generation == requestGeneration,
                      self.isConnected else {

                    reference.cancelDisconnectOperations()
                    return
                }

                if let error {

                    self.phase = .idle
                    self.isUpdating = false
                    self.wantsToFind = false

                    self.errorMessage =
                        error.localizedDescription

                    return
                }

                guard self.wantsToFind else {

                    self.phase = .idle
                    self.isUpdating = false

                    reference.cancelDisconnectOperations()
                    return
                }

                self.publishFinding(
                    reference: reference,
                    requestGeneration: requestGeneration
                )
            }
        }
    }

    // MARK: - Publish Finding

    private func publishFinding(
        reference: DatabaseReference,
        requestGeneration: Int
    ) {

        phase = .publishing
        isUpdating = true

        reference.setValue(true) {
            [weak self] error, _ in

            Task { @MainActor [weak self] in

                guard let self else {

                    if error == nil {
                        reference.removeValue()
                    }

                    return
                }

                // This write belongs to an
                // already disconnected session.
                // Clean it up before forgetting it.

                guard self.generation == requestGeneration,
                      self.isConnected else {

                    if error == nil {
                        reference.removeValue {
                            removalError, _ in

                            if removalError == nil {
                                reference
                                    .cancelDisconnectOperations()
                            }
                        }
                    } else {
                        reference.cancelDisconnectOperations()
                    }

                    return
                }

                if let error {

                    self.phase = .idle
                    self.isUpdating = false
                    self.wantsToFind = false
                    self.isFinding = false

                    self.errorMessage =
                        error.localizedDescription

                    reference.cancelDisconnectOperations()
                    return
                }

                // Stop may have been requested
                // while setValue(true) was running.

                guard self.wantsToFind else {

                    self.removeFindingFlag(
                        reference: reference,
                        requestGeneration: requestGeneration
                    )

                    return
                }

                self.phase = .active
                self.isUpdating = false
                self.isFinding = true
                self.errorMessage = nil
            }
        }
    }

    // MARK: - Remove Finding

    private func removeFindingFlag(
        reference: DatabaseReference,
        requestGeneration: Int
    ) {

        guard phase != .removing else {
            return
        }

        phase = .removing
        isUpdating = true
        isFinding = false

        reference.removeValue {
            [weak self] error, _ in

            Task { @MainActor [weak self] in

                // On successful removal,
                // cancel the server cleanup too.

                if error == nil {
                    reference.cancelDisconnectOperations()
                }

                guard let self,
                      self.generation == requestGeneration else {
                    return
                }

                self.phase = .idle
                self.isUpdating = false
                self.isFinding = false

                if let error {

                    // Keep onDisconnect armed if
                    // the removal failed.

                    self.wantsToFind = false
                    self.errorMessage =
                        error.localizedDescription

                    return
                }

                self.errorMessage = nil

                // Start again only after the
                // previous remove was confirmed.

                self.advance()
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {

        let previousReference = myReference
        let previousPhase = phase

        // Invalidate old session callbacks.
        // An in-flight publish callback will
        // still clean up its own reference.

        generation += 1
        wantsToFind = false

        switch previousPhase {

        case .active:

            // We know true was published.
            // Remove it once.

            if let reference = previousReference {

                reference.removeValue { error, _ in

                    if error == nil {
                        reference
                            .cancelDisconnectOperations()
                    }
                }
            }

        case .registering:

            // Registration callback sees the
            // changed generation and cancels
            // the disconnect operation.

            break

        case .publishing:

            // Publishing callback sees the
            // changed generation and removes
            // the true value if it succeeded.

            break

        case .removing:

            // Removal is already in flight.
            // Do not send a duplicate remove.

            break

        case .idle:

            // No finding was published.
            // No Firebase write is needed.

            break
        }

        // Stop the peer listener.

        if let reference = peerReference,
           let observer = peerObserver {

            reference.removeObserver(
                withHandle: observer
            )
        }

        myReference = nil
        peerReference = nil
        peerObserver = nil
        activeSessionID = nil

        phase = .idle

        isConnected = false
        isFinding = false
        isPeerFinding = false
        isUpdating = false

        errorMessage = nil
    }

    // MARK: - Deinit

    deinit {

        if let reference = peerReference,
           let observer = peerObserver {

            reference.removeObserver(
                withHandle: observer
            )
        }
    }
}
