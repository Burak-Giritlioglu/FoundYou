import Foundation
import Combine
import CoreLocation
import simd

@MainActor
final class TrackingCoordinator: ObservableObject {

    // MARK: - Managers

    let location = LocationManager()
    let heading = HeadingManager()
    let motion = MotionManager()

    let live = LiveLocationManager()

    let nearby = NearbyInteractionManager()
    let tokenExchange = UWBTokenExchangeManager()

    let navigation = NavigationManager()

    // MARK: - Published State

    @Published private(set) var deviceQuaternion =
        simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1))

    @Published private(set) var locationError: String?
    @Published private(set) var liveError: String?
    @Published private(set) var nearbyError: String?
    @Published private(set) var tokenError: String?

    @Published private(set) var isTracking = false

    // MARK: - Internal State

    private var activeSession: PairingSession?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        observeManagers()
    }

    // MARK: - Start Tracking

    func start(session: PairingSession) {

        guard !isTracking else {
            return
        }

        activeSession = session
        isTracking = true

        navigation.reset()

        // Firebase location synchronization
        live.start(session: session)

        // GPS and device sensors
        location.start()
        heading.start()
        motion.start()

        // Nearby Interaction (UWB)
        nearby.prepare()

        if let token = nearby.discoveryTokenData {
            tokenExchange.start(
                session: session,
                myTokenData: token
            )
        }

        updateNavigation()
    }

    // MARK: - Stop Tracking

    func stop() {

        guard isTracking else {
            return
        }

        isTracking = false
        activeSession = nil

        tokenExchange.stop()
        nearby.stop()

        live.stop()
        location.stop()
        heading.stop()
        motion.stop()

        navigation.reset()

        locationError = nil
        liveError = nil
        nearbyError = nil
        tokenError = nil
    }

    // MARK: - Manager Observers

    private func observeManagers() {

        // My GPS location
        location.$location
            .sink { [weak self] newLocation in
                guard let self else { return }

                if self.isTracking,
                   let newLocation {
                    self.live.updateMyLocation(newLocation)
                }

                self.updateNavigation()
            }
            .store(in: &cancellables)

        // Friend's GPS location
        live.$friendLocation
            .sink { [weak self] _ in
                self?.updateNavigation()
            }
            .store(in: &cancellables)

        // UWB distance
        nearby.$distance
            .sink { [weak self] _ in
                self?.updateNavigation()
            }
            .store(in: &cancellables)

        // UWB direction
        nearby.$direction
            .sink { [weak self] _ in
                self?.updateNavigation()
            }
            .store(in: &cancellables)

        // New UWB measurement
        nearby.$measurementID
            .sink { [weak self] _ in
                self?.updateNavigation()
            }
            .store(in: &cancellables)

        // Device orientation
        motion.$quaternion
            .sink { [weak self] quaternion in
                guard let self else { return }

                self.deviceQuaternion = quaternion
                self.updateNavigation()
            }
            .store(in: &cancellables)

        // Peer UWB discovery token
        tokenExchange.$peerTokenData
            .sink { [weak self] tokenData in
                guard let self,
                      self.isTracking,
                      let tokenData else {
                    return
                }

                self.nearby.start(
                    peerTokenData: tokenData
                )
            }
            .store(in: &cancellables)

        // MARK: - Error Observers

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

    // MARK: - Navigation Updates

    private func updateNavigation() {

        guard isTracking else {
            return
        }

        navigation.update(
            myLocation: location.location,
            friendLocation: live.friendLocation,
            uwbDistance: nearby.distance,
            uwbDirection: nearby.direction,
            uwbMeasurementID: nearby.measurementID,
            deviceQuaternion: motion.quaternion
        )
    }
}
