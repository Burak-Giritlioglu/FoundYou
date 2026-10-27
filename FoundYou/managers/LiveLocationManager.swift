
import Foundation
import Combine
import CoreLocation
import FirebaseAuth
import FirebaseDatabase

@MainActor
final class LiveLocationManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var friendLocation: CLLocation?
    @Published private(set) var isSharing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasUploadedInitialLocation = false

    // MARK: - Firebase

    private let db = Database.database(
        url: "https://foundyou-5a965-default-rtdb.europe-west1.firebasedatabase.app"
    )

    private var friendReference: DatabaseReference?
    private var friendObserver: DatabaseHandle?

    // MARK: - Session

    private var sessionID: String?
    private var myUID: String?
    private var peerUID: String?

    private var generation = 0
    private var isShuttingDown = false

    // MARK: - GPS State

    private let gpsFilter = GPSFilter()

    private var isReceiving = false
    private var peerRequestsMyLocation = false
    private var gpsUploadsPaused = false

    private var latestLocalLocation: CLLocation?

    private var uploadInProgress = false
    private var cleanupInProgress = false
    private var cleanupFailed = false

    // MARK: - Async Operations

    private var uploadWaiters:
        [UUID: CheckedContinuation<Void, Error>] = [:]

    private var cleanupWaiters:
        [UUID: CheckedContinuation<Void, Error>] = [:]

    private let operationTimeout: TimeInterval = 8

    private enum CleanupError: LocalizedError {
        case timedOut
        case interrupted

        var errorDescription: String? {
            switch self {
            case .timedOut:
                return "Location cleanup timed out. Please check your connection."
            case .interrupted:
                return "Location cleanup was interrupted."
            }
        }
    }

    // MARK: - Start Session

    func start(session: PairingSession) {

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

        if sessionID == session.id && myUID == uid {
            return
        }

        // This resets local state, not server operations.
        // Previous Firebase requests retain their
        // original database references.
        stop()

        sessionID = session.id
        myUID = uid
        peerUID = otherUID

        gpsFilter.configure(
            sessionID: session.id,
            userID: uid
        )

        hasUploadedInitialLocation = false
        errorMessage = nil
    }

    // MARK: - Receive Friend Location

    func setReceivingFriendLocation(_ enabled: Bool) {

        if !enabled {
            stopReceiving()
            return
        }

        guard let sessionID,
              let peerUID,
              !isReceiving else {
            return
        }

        isReceiving = true

        let currentGeneration = generation

        let reference = db.reference()
            .child("locations")
            .child(sessionID)
            .child(peerUID)

        friendReference = reference

        friendObserver = reference.observe(
            .value,
            with: { [weak self] snapshot in

                Task { @MainActor [weak self] in

                    guard let self,
                          self.generation == currentGeneration,
                          self.isReceiving else {
                        return
                    }

                    self.receiveFriendLocation(
                        snapshot.value
                    )
                }
            },
            withCancel: { [weak self] error in

                Task { @MainActor [weak self] in

                    guard let self,
                          self.generation == currentGeneration,
                          self.isReceiving else {
                        return
                    }

                    self.errorMessage =
                        error.localizedDescription
                }
            }
        )
    }

    private func receiveFriendLocation(_ value: Any?) {

        guard let data = value as? [String: Any],
              let latitude = data["latitude"] as? NSNumber,
              let longitude = data["longitude"] as? NSNumber,
              let accuracy = data["accuracy"] as? NSNumber,
              let updatedAt = data["updatedAt"] as? NSNumber else {

            friendLocation = nil
            return
        }

        let coordinate = CLLocationCoordinate2D(
            latitude: latitude.doubleValue,
            longitude: longitude.doubleValue
        )

        guard CLLocationCoordinate2DIsValid(coordinate),
              accuracy.doubleValue >= 0 else {

            friendLocation = nil
            return
        }

        // Preserve the server timestamp for R1.
        // Do not discard a coordinate merely
        // because the friend has not moved.

        let timestamp = Date(
            timeIntervalSince1970:
                updatedAt.doubleValue / 1000
        )

        friendLocation = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: accuracy.doubleValue,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    private func stopReceiving() {

        isReceiving = false

        if let reference = friendReference,
           let observer = friendObserver {

            reference.removeObserver(
                withHandle: observer
            )
        }

        friendReference = nil
        friendObserver = nil
        friendLocation = nil
    }

    // MARK: - GPS Sharing State

    private func prepareNewGPSSharing() {
        gpsFilter.reset()
        hasUploadedInitialLocation = false
    }

    private func resumeSharingIfAllowed() {

        guard !isShuttingDown,
              !cleanupInProgress,
              !cleanupFailed,
              peerRequestsMyLocation,
              !gpsUploadsPaused,
              sessionID != nil,
              myUID != nil else {

            isSharing = false
            return
        }

        isSharing = true

        // Feed the latest local reading into
        // GPSFilter without forcing an upload.

        if let latestLocalLocation {
            updateMyLocation(latestLocalLocation)
        }
    }

    // MARK: - Peer Finding State

    func setLocationRequestedByPeer(_ requested: Bool) {

        guard sessionID != nil,
              myUID != nil else {
            return
        }

        // Never restart sharing during
        // connection shutdown.

        guard !isShuttingDown else {
            isSharing = false
            return
        }

        let wasRequested = peerRequestsMyLocation

        peerRequestsMyLocation = requested

        if requested {

            if !wasRequested {

                if cleanupFailed {

                    // Remove any potentially stale record
                    // before starting a new search.

                    startCleanupIfNeeded()

                } else if !cleanupInProgress {

                    prepareNewGPSSharing()
                }
            }

            resumeSharingIfAllowed()
            return
        }

        isSharing = false

        if wasRequested {
            startCleanupIfNeeded()
        }
    }

    // MARK: - GPS Pause Compatibility

    func setGPSUploadsPaused(_ paused: Bool) {

        gpsUploadsPaused = paused
        resumeSharingIfAllowed()
    }

    // MARK: - Local GPS

    func updateMyLocation(_ location: CLLocation) {

        latestLocalLocation = location

        guard isSharing,
              !isShuttingDown,
              !cleanupInProgress,
              !cleanupFailed,
              !gpsUploadsPaused,
              peerRequestsMyLocation,
              !uploadInProgress,
              let sessionID,
              let uid = myUID else {
            return
        }

        guard let candidate = gpsFilter.process(location) else {
            return
        }

        let currentGeneration = generation

        let reference = db.reference()
            .child("locations")
            .child(sessionID)
            .child(uid)

        let data: [String: Any] = [
            "latitude": candidate.coordinate.latitude,
            "longitude": candidate.coordinate.longitude,
            "accuracy": candidate.horizontalAccuracy,
            "updatedAt": ServerValue.timestamp()
        ]

        // Set this synchronously before submitting
        // the Firebase write. Cleanup sees it.

        uploadInProgress = true

        reference.setValue(data) { [weak self] error, _ in

            Task { @MainActor [weak self] in

                guard let self,
                      self.generation == currentGeneration else {
                    return
                }

                self.uploadInProgress = false

                // Wake cleanup, even when the upload failed.
                self.finishUploadWaiters(error: nil)

                if let error {

                    self.errorMessage =
                        error.localizedDescription
                    return
                }

                // A successful old upload must not
                // update GPSFilter for a new search
                // or during cleanup.

                guard !self.cleanupInProgress,
                      !self.isShuttingDown,
                      self.peerRequestsMyLocation else {
                    return
                }

                self.gpsFilter.markUploaded(candidate)
                self.hasUploadedInitialLocation = true
                self.errorMessage = nil
            }
        }
    }

    // MARK: - Waiter Helpers

    private func finishUploadWaiters(error: Error?) {

        let waiters = uploadWaiters
        uploadWaiters.removeAll()

        for continuation in waiters.values {

            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    private func finishCleanupWaiters(error: Error?) {

        let waiters = cleanupWaiters
        cleanupWaiters.removeAll()

        for continuation in waiters.values {

            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    // MARK: - Internal Upload Wait

    // No timeout here: the deletion task must
    // not overtake an unresolved Firebase write.

    private func waitForUploadCompletion() async {

        guard uploadInProgress else {
            return
        }

        let id = UUID()

        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in

            // Bridge the nonthrowing internal wait
            // through the shared throwing waiters.

            Task { @MainActor in

                do {

                    try await withCheckedThrowingContinuation {
                        (inner: CheckedContinuation<Void, Error>) in

                        uploadWaiters[id] = inner
                    }

                } catch {
                    // A local reset can interrupt the wait.
                }

                continuation.resume()
            }
        }
    }

    // MARK: - User-Facing Upload Wait

    func stopUploadsAndWait() async throws {

        isSharing = false

        guard uploadInProgress else {
            return
        }

        let id = UUID()
        let timeout = operationTimeout

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in

            uploadWaiters[id] = continuation

            Task { @MainActor [weak self] in

                do {
                    try await Task.sleep(
                        for: .seconds(timeout)
                    )
                } catch {
                    return
                }

                guard let self,
                      let waiter =
                        self.uploadWaiters.removeValue(forKey: id)
                else {
                    return
                }

                // The Firebase write is not cancelled.
                waiter.resume(
                    throwing: CleanupError.timedOut
                )
            }
        }
    }

    // MARK: - Connection Shutdown

    func prepareForConnectionShutdown() {

        isShuttingDown = true
        peerRequestsMyLocation = false
        isSharing = false
    }

    func cancelConnectionShutdown() {

        // Used only when End Connection failed
        // and the pairing is still connected.

        isShuttingDown = false
        isSharing = false

        // TrackingCoordinator will restore
        // peer finding state explicitly.
    }

    // MARK: - Firebase Cleanup

    private func startCleanupIfNeeded() {

        guard !cleanupInProgress,
              let sessionID,
              let uid = myUID else {
            return
        }

        cleanupInProgress = true
        cleanupFailed = false
        isSharing = false

        let currentGeneration = generation

        let reference = db.reference()
            .child("locations")
            .child(sessionID)
            .child(uid)

        // This task intentionally continues if
        // the UI's eight-second wait times out.

        Task { [weak self] in

            guard let self else {
                return
            }

            // The last write must resolve before
            // the deletion is submitted.

            await self.waitForUploadCompletion()

            let result: Result<Void, Error>

            do {

                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in

                    reference.removeValue { error, _ in

                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }

                result = .success(())

            } catch {

                result = .failure(error)
            }

            guard self.generation == currentGeneration else {
                return
            }

            self.cleanupInProgress = false

            switch result {

            case .success:

                self.cleanupFailed = false
                self.prepareNewGPSSharing()

                self.finishCleanupWaiters(error: nil)

                // A fresh search may have started
                // while the old deletion was pending.

                self.resumeSharingIfAllowed()

            case .failure(let error):

                self.cleanupFailed = true
                self.isSharing = false

                self.errorMessage =
                    error.localizedDescription

                self.finishCleanupWaiters(error: error)
            }
        }
    }

    // MARK: - Await Firebase Cleanup

    func removeSharedLocation() async throws {

        guard sessionID != nil,
              myUID != nil else {
            return
        }

        startCleanupIfNeeded()

        guard cleanupInProgress else {

            if cleanupFailed {
                throw CleanupError.interrupted
            }

            return
        }

        let id = UUID()
        let timeout = operationTimeout

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in

            cleanupWaiters[id] = continuation

            Task { @MainActor [weak self] in

                do {
                    try await Task.sleep(
                        for: .seconds(timeout)
                    )
                } catch {
                    return
                }

                guard let self,
                      let waiter =
                        self.cleanupWaiters.removeValue(forKey: id)
                else {
                    return
                }

                // Timeout does not cancel deletion.
                waiter.resume(
                    throwing: CleanupError.timedOut
                )
            }
        }
    }

    // MARK: - Stop Local Session

    func stop() {

        generation += 1

        isSharing = false
        peerRequestsMyLocation = false
        gpsUploadsPaused = false
        isShuttingDown = false

        finishUploadWaiters(
            error: CleanupError.interrupted
        )

        finishCleanupWaiters(
            error: CleanupError.interrupted
        )

        stopReceiving()

        sessionID = nil
        myUID = nil
        peerUID = nil

        uploadInProgress = false
        cleanupInProgress = false
        cleanupFailed = false

        latestLocalLocation = nil

        gpsFilter.reset()

        friendLocation = nil
        hasUploadedInitialLocation = false
        errorMessage = nil

        // Existing Firebase callbacks are not
        // cancelled by this local reset.
        //
        // Generation checks prevent old callbacks
        // from changing this manager's new session.
        //
        // Server-side authorization remains
        // the final protection against late writes.
    }

    deinit {

        if let reference = friendReference,
           let observer = friendObserver {

            reference.removeObserver(
                withHandle: observer
            )
        }
    }
}
