
import Foundation
import Combine
import CoreLocation
import simd

@MainActor
final class TrackingCoordinator: ObservableObject {

    // MARK: - Managers

    let finding = FindingStateManager()

    let location = LocationManager()
    let heading = HeadingManager()
    let motion = MotionManager()

    let live = LiveLocationManager()

    let nearby = NearbyInteractionManager()
    let tokenExchange = UWBTokenExchangeManager()

    let navigation = NavigationManager()
    let foundDetection = FoundDetectionManager()

    // MARK: - Published State

    @Published private(set) var isConnected = false
    @Published private(set) var isFinding = false
    @Published private(set) var isPeerFinding = false
    @Published private(set) var isTracking = false
    @Published private(set) var hasFoundFriend = false

    @Published private(set) var deviceQuaternion = simd_quatd(
        ix: 0, iy: 0, iz: 0, r: 1
    )

    @Published private(set) var locationError: String?
    @Published private(set) var liveError: String?
    @Published private(set) var nearbyError: String?
    @Published private(set) var tokenError: String?
    @Published private(set) var findingError: String?

    // MARK: - Session

    private var activeSession: PairingSession?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Sensor State

    private var currentMyLocation: CLLocation?
    private var currentFriendLocation: CLLocation?

    private var currentUWBDistance: Float?
    private var currentUWBDirection: SIMD3<Float>?
    private var currentUWBMeasurementID: UInt64 = 0

    private var currentQuaternion = simd_quatd(
        ix: 0, iy: 0, iz: 0, r: 1
    )

    private var refreshTask: Task<Void, Never>?

    private var lastReceivingState = false
    private var lastSharingState = false

    // MARK: - Connection Shutdown

    @Published private(set) var isEndingConnection = false

    // MARK: - Initialization

    init() {
        observeManagers()
    }

    // MARK: - Connection

    func connect(session: PairingSession) {

        guard session.status == .connected else {
            findingError = "Connection is not approved."
            return
        }

        if isConnected && activeSession?.id == session.id {
            return
        }

        disconnect()

        activeSession = session

        // Configure GPS sharing state for the
        // entire paired session.
        //
        // No Firebase GPS upload starts here.

        live.start(session: session)

        // Keep Core Location available while paired,
        // including when no one is currently finding.
        //
        // Background execution depends on the
        // user's authorization and iOS behavior.

        location.setBackgroundTrackingEnabled(true)
        location.start()

        // Listen for finding requests.

        finding.connect(session: session)

        isConnected = finding.isConnected
        isPeerFinding = finding.isPeerFinding
        findingError = finding.errorMessage

        refreshTrackingState()
    }

    // MARK: - Start Finding

    func startFinding() {

        guard isConnected,
              activeSession != nil,
              !isFinding,
              !finding.isUpdating,
              !isEndingConnection else {
            return
        }

        hasFoundFriend = false
        foundDetection.reset()

        finding.startFinding()
    }

    // MARK: - Stop Finding

    func stopFinding() {

        guard isConnected,
              isFinding || finding.isUpdating else {
            return
        }

        isFinding = false

        finding.stopFinding()
        refreshTrackingState()
    }

    // MARK: - Tracking Lifecycle

    private func refreshTrackingState() {

        guard isConnected,
              let session = activeSession else {
            return
        }

        if isEndingConnection {
            return
        }

        // Direction and proximity sensors are only
        // needed while someone is actively finding.
        //
        // GPS itself stays available while paired.

        let shouldTrack = isFinding || isPeerFinding

        if shouldTrack && !isTracking {

            startSensors(session: session)

        } else if !shouldTrack && isTracking {

            stopSensors()
        }

        guard isTracking else {
            return
        }

        // Receive the friend's GPS only
        // while we are finding them.

        if lastReceivingState != isFinding {

            lastReceivingState = isFinding
            live.setReceivingFriendLocation(isFinding)
        }

        // Publish our GPS only while the
        // friend is finding us.

        if lastSharingState != isPeerFinding {

            lastSharingState = isPeerFinding

            live.setLocationRequestedByPeer(isPeerFinding)

            if isPeerFinding,
               let currentLocation = currentMyLocation,
               currentLocation.horizontalAccuracy >= 0,
               abs(
                   currentLocation.timestamp
                       .timeIntervalSinceNow
               ) < 10 {

                live.updateMyLocation(currentLocation)
            }
        }
    }

    // MARK: - Start Direction Sensors

    private func startSensors(session: PairingSession) {

        guard !isTracking,
              !isEndingConnection else {
            return
        }

        resetSensorSnapshots()

        navigation.reset()
        foundDetection.reset()

        lastReceivingState = false
        lastSharingState = false

        isTracking = true

        // R4:
        // GPS and LiveLocationManager are already
        // initialized in connect(session:).
        //
        // Do NOT call live.start() here.
        // Do NOT restart location here.

        heading.start()
        motion.start()

        // Use an existing fresh GPS reading
        // for immediate local navigation.

        if let existing = location.location,
           existing.horizontalAccuracy >= 0,
           abs(existing.timestamp.timeIntervalSinceNow) < 10 {

            currentMyLocation = existing
        }

        nearby.prepare()

        if let token = nearby.discoveryTokenData {

            tokenExchange.start(
                session: session,
                myTokenData: token
            )
        }

        updateNavigation()
        startLocalRefresh()
    }

    // MARK: - Stop Direction Sensors

    private func stopSensors() {

        guard isTracking else {
            return
        }

        isTracking = false

        refreshTask?.cancel()
        refreshTask = nil

        // Stop searching and GPS sharing.
        // LiveLocationManager handles Firebase
        // cleanup asynchronously.

        live.setLocationRequestedByPeer(false)
        live.setReceivingFriendLocation(false)

        lastReceivingState = false
        lastSharingState = false

        tokenExchange.stop()
        nearby.stop()

        // R4:
        // Do not stop location here.
        //
        // Keep Core Location available during
        // the paired session, even if both
        // users are temporarily not finding.

        heading.stop()
        motion.stop()

        resetSensorSnapshots()

        navigation.reset()
        foundDetection.reset()
    }

    // MARK: - Local Refresh

    // Updates local navigation state.
    // Does not poll Firebase or upload GPS.

    private func startLocalRefresh() {

        refreshTask?.cancel()

        refreshTask = Task { @MainActor [weak self] in

            while !Task.isCancelled {

                do {
                    try await Task.sleep(
                        for: .seconds(1)
                    )
                } catch {
                    break
                }

                guard let self,
                      self.isTracking,
                      !self.isEndingConnection else {
                    break
                }

                self.updateNavigation()
            }
        }
    }

    // MARK: - Navigation Update

    private func updateNavigation() {

        guard isTracking,
              !isEndingConnection else {
            return
        }

        navigation.update(
            myLocation: currentMyLocation,
            friendLocation: currentFriendLocation,
            uwbDistance: currentUWBDistance,
            uwbDirection: currentUWBDirection,
            uwbMeasurementID: currentUWBMeasurementID,
            deviceQuaternion: currentQuaternion
        )

        // UWB availability on this phone must not
        // disable GPS sharing for the friend.
        //
        // The friend may still need GPS fallback.

        checkFoundYou()
    }

    // MARK: - Found Detection

    private func checkFoundYou() {

        guard isFinding,
              !isEndingConnection else {
            return
        }

        let found = foundDetection.update(
            distance: navigation.isUWBPreferred
                ? currentUWBDistance
                : nil,
            measurementID: currentUWBMeasurementID,
            measuredAt: nearby.lastMeasurementAt
        )

        if found {
            completeFinding()
        }
    }

    private func completeFinding() {

        guard isFinding else {
            return
        }

        hasFoundFriend = true

        stopFinding()

        print("FOUND YOU!")
    }

    // MARK: - Prepare Connection Shutdown

    func prepareForEndConnection() async throws {

        guard isConnected,
              activeSession != nil else {
            return
        }

        guard !isEndingConnection else {
            return
        }

        isEndingConnection = true

        refreshTask?.cancel()
        refreshTask = nil

        do {

            // Prevent GPS sharing from restarting.

            live.prepareForConnectionShutdown()

            // Wait for the current write if one
            // is still in progress.

            try await live.stopUploadsAndWait()

            // Remove our shared Firebase location
            // before the pairing session is ended.

            try await live.removeSharedLocation()

        } catch {

            // Restore tracking if cleanup
            // failed while still connected.

            cancelEndConnection()
            throw error
        }

        // ContentView will end the pairing.
    }

    // MARK: - Cancel Connection Shutdown

    func cancelEndConnection() {

        guard isEndingConnection else {
            return
        }

        live.cancelConnectionShutdown()

        isEndingConnection = false

        // Restore sharing only if the friend
        // is still actively finding us.

        live.setLocationRequestedByPeer(isPeerFinding)

        if isTracking {
            startLocalRefresh()
        }

        refreshTrackingState()
    }

    // MARK: - Manager Observers

    private func observeManagers() {

        // MARK: Connection State

        finding.$isConnected
            .sink { [weak self] connected in

                guard let self else {
                    return
                }

                self.isConnected = connected

                if !connected {

                    self.isFinding = false
                    self.isPeerFinding = false

                    self.stopSensors()

                    // Stop background GPS if the
                    // connection ended remotely.
                    self.location.stop()
                }
            }
            .store(in: &cancellables)

        // MARK: Our Finding State

        finding.$isFinding
            .sink { [weak self] confirmed in

                guard let self,
                      self.isConnected,
                      self.activeSession != nil else {
                    return
                }

                self.isFinding = confirmed
                self.refreshTrackingState()
            }
            .store(in: &cancellables)

        // MARK: Friend's Finding State

        finding.$isPeerFinding
            .sink { [weak self] peerFinding in

                guard let self else {
                    return
                }

                self.isPeerFinding = peerFinding
                self.refreshTrackingState()
            }
            .store(in: &cancellables)

        // MARK: Finding Errors

        finding.$errorMessage
            .sink { [weak self] message in

                guard let self else {
                    return
                }

                self.findingError = message

                if message != nil,
                   !self.finding.isFinding,
                   self.isFinding {

                    self.isFinding = false
                    self.refreshTrackingState()
                }
            }
            .store(in: &cancellables)

        // MARK: Local GPS

        location.$location
            .sink { [weak self] newLocation in

                guard let self else {
                    return
                }

                self.currentMyLocation = newLocation

                // R4:
                // GPS measurements must reach
                // LiveLocationManager even when
                // the direction sensors are stopped.
                //
                // LiveLocationManager decides whether
                // Firebase upload is permitted.

                guard self.isConnected,
                      !self.isEndingConnection else {
                    return
                }

                if let newLocation {
                    self.live.updateMyLocation(newLocation)
                }

                // Only update the direction arrow
                // during an active finding operation.

                if self.isTracking {
                    self.updateNavigation()
                }
            }
            .store(in: &cancellables)

        // MARK: Friend GPS

        live.$friendLocation
            .sink { [weak self] newLocation in

                guard let self else {
                    return
                }

                self.currentFriendLocation = newLocation
                self.updateNavigation()
            }
            .store(in: &cancellables)

        // MARK: UWB Distance

        nearby.$distance
            .sink { [weak self] distance in

                guard let self else {
                    return
                }

                self.currentUWBDistance = distance
                self.updateNavigation()
            }
            .store(in: &cancellables)

        // MARK: UWB Direction

        nearby.$direction
            .sink { [weak self] direction in

                guard let self else {
                    return
                }

                self.currentUWBDirection = direction
                self.updateNavigation()
            }
            .store(in: &cancellables)

        // MARK: UWB Measurement Revision

        nearby.$measurementID
            .sink { [weak self] measurementID in

                guard let self else {
                    return
                }

                self.currentUWBMeasurementID = measurementID
                self.updateNavigation()
            }
            .store(in: &cancellables)

        // MARK: Device Orientation

        motion.$quaternion
            .sink { [weak self] quaternion in

                guard let self else {
                    return
                }

                self.currentQuaternion = quaternion
                self.deviceQuaternion = quaternion

                self.updateNavigation()
            }
            .store(in: &cancellables)

        // MARK: Local UWB Token

        nearby.$discoveryTokenRevision
            .dropFirst()
            .sink { [weak self] _ in

                guard let self,
                      self.isTracking,
                      !self.isEndingConnection,
                      let session = self.activeSession,
                      let token = self.nearby.discoveryTokenData else {
                    return
                }

                self.tokenExchange.start(
                    session: session,
                    myTokenData: token
                )
            }
            .store(in: &cancellables)

        // MARK: Friend UWB Token

        tokenExchange.$peerTokenData
            .sink { [weak self] token in

                guard let self,
                      self.isTracking,
                      !self.isEndingConnection,
                      let token else {
                    return
                }

                self.nearby.start(
                    peerTokenData: token
                )
            }
            .store(in: &cancellables)

        // MARK: Errors

        location.$errorMessage
            .sink { [weak self] message in
                self?.locationError = message
            }
            .store(in: &cancellables)

        live.$errorMessage
            .sink { [weak self] message in
                self?.liveError = message
            }
            .store(in: &cancellables)

        nearby.$errorMessage
            .sink { [weak self] message in
                self?.nearbyError = message
            }
            .store(in: &cancellables)

        tokenExchange.$errorMessage
            .sink { [weak self] message in
                self?.tokenError = message
            }
            .store(in: &cancellables)
    }

    // MARK: - Reset Sensor State

    private func resetSensorSnapshots() {

        currentMyLocation = nil
        currentFriendLocation = nil

        currentUWBDistance = nil
        currentUWBDirection = nil
        currentUWBMeasurementID = 0

        currentQuaternion = simd_quatd(
            ix: 0, iy: 0, iz: 0, r: 1
        )

        deviceQuaternion = currentQuaternion
    }

    // MARK: - Disconnect

    func disconnect() {

        // Block new Firebase GPS writes immediately.

        live.prepareForConnectionShutdown()

        // Attempt to remove our location.
        // A timeout does not guarantee that
        // Firebase has completed the deletion.

        let locationManager = live

        Task { @MainActor in

            do {
                try await locationManager.removeSharedLocation()
            } catch {
                // The deletion may still be pending
                // in Firebase after a local timeout.
            }
        }

        stopSensors()

        // Stop GPS only when the pairing ends.
        location.stop()

        finding.disconnect()

        activeSession = nil

        isConnected = false
        isFinding = false
        isPeerFinding = false
        isTracking = false
        isEndingConnection = false
        hasFoundFriend = false

        findingError = nil
        locationError = nil
        liveError = nil
        nearbyError = nil
        tokenError = nil
    }

    // MARK: - Compatibility

    func start(session: PairingSession) {
        connect(session: session)
    }

    func stop() {
        disconnect()
    }
}
