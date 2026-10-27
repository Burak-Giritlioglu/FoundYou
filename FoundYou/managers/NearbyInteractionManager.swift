import Foundation
import Combine
import NearbyInteraction
import simd

@MainActor
final class NearbyInteractionManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isSupported = false
    @Published private(set) var isRunning = false

    @Published private(set) var distance: Float?
    @Published private(set) var direction: SIMD3<Float>?

    @Published private(set) var measurementID: UInt64 = 0
    @Published private(set) var lastMeasurementAt: Date?

    @Published private(set) var errorMessage: String?

    // Increases whenever a fresh NISession is created.
    // TrackingCoordinator will observe this value
    // and republish the discovery token to Firebase.

    @Published private(set) var discoveryTokenRevision: UInt64 = 0

    // MARK: - Nearby Interaction State

    private var session: NISession?
    private var peerConfiguration: NINearbyPeerConfiguration?

    private var isSuspended = false

    // MARK: - Task Management

    private var measurementTimeoutTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    private var generation: UInt64 = 0

    // MARK: - Recovery Configuration

    private var recoveryAttempts = 0
    private let maxRecoveryAttempts = 3

    // MARK: - Discovery Token

    var discoveryTokenData: Data? {

        guard let token = session?.discoveryToken else {
            return nil
        }

        do {
            return try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()

        let capabilities = NISession.deviceCapabilities

        isSupported = capabilities.supportsPreciseDistanceMeasurement

        print("========== UWB CAPABILITIES ==========")
        print(
            "Precise distance:",
            capabilities.supportsPreciseDistanceMeasurement
        )
        print(
            "Direction measurement:",
            capabilities.supportsDirectionMeasurement
        )
        print("======================================")
    }

    // MARK: - Prepare

    func prepare() {

        guard isSupported else {
            errorMessage = "This device does not support UWB."
            return
        }

        stop()

        installNewSession()
    }

    // MARK: - Create New Session

    private func installNewSession() {

        guard isSupported else {
            return
        }

        let newSession = NISession()
        newSession.delegate = self

        session = newSession
        peerConfiguration = nil

        isRunning = false
        isSuspended = false

        clearMeasurement()

        errorMessage = nil

        // Notify TrackingCoordinator that our discovery
        // token must be shared again.

        discoveryTokenRevision &+= 1
    }

    // MARK: - Start Ranging

    func start(peerTokenData: Data) {

        guard let session else {
            errorMessage = "UWB session is not ready."
            return
        }

        do {

            guard let token = try NSKeyedUnarchiver
                .unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: peerTokenData
                ) else {
                errorMessage = "Could not read the friend's UWB token."
                return
            }

            let configuration = NINearbyPeerConfiguration(
                peerToken: token
            )

            peerConfiguration = configuration

            // If iOS has suspended this session,
            // resume ranging when suspension ends.

            guard !isSuspended else {
                return
            }

            session.run(configuration)

            isRunning = true
            errorMessage = nil

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Receive Measurements

    private func receiveMeasurement(
        distance newDistance: Float?,
        direction newDirection: SIMD3<Float>?
    ) {

        guard isRunning, !isSuspended else {
            return
        }

        let validDistance: Float?

        if let newDistance,
           newDistance.isFinite,
           newDistance >= 0 {

            validDistance = newDistance

        } else {
            validDistance = nil
        }

        let validDirection: SIMD3<Float>?

        if let newDirection,
           newDirection.x.isFinite,
           newDirection.y.isFinite,
           newDirection.z.isFinite,
           simd_length(newDirection) > 0.001 {

            validDirection = newDirection

        } else {
            validDirection = nil
        }

        distance = validDistance
        direction = validDirection

        measurementID &+= 1
        lastMeasurementAt = Date()

        // A valid ranging result means the new session
        // successfully recovered.

        if validDistance != nil {
            recoveryAttempts = 0
            errorMessage = nil
        }

        restartMeasurementTimeout()
    }

    // MARK: - Measurement Timeout

    private func restartMeasurementTimeout() {

        measurementTimeoutTask?.cancel()

        let currentGeneration = generation

        measurementTimeoutTask = Task { @MainActor [weak self] in

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            guard let self,
                  self.generation == currentGeneration else {
                return
            }

            self.clearMeasurement()
        }
    }

    private func clearMeasurement() {
        distance = nil
        direction = nil
        lastMeasurementAt = nil
    }

    // MARK: - Session Invalidation

    private func invalidateCurrentSession(
        with error: Error
    ) {

        generation &+= 1

        measurementTimeoutTask?.cancel()
        measurementTimeoutTask = nil

        session?.delegate = nil
        session = nil
        peerConfiguration = nil

        isRunning = false
        isSuspended = false

        clearMeasurement()

        errorMessage = "UWB connection lost. Reconnecting..."

        scheduleRecovery()
    }

    // MARK: - Automatic Recovery

    private func scheduleRecovery() {

        recoveryTask?.cancel()
        recoveryTask = nil

        guard isSupported else {
            return
        }

        guard recoveryAttempts < maxRecoveryAttempts else {
            errorMessage = "UWB could not reconnect. GPS remains available."
            return
        }

        recoveryAttempts += 1

        // Short increasing delay between attempts.
        // 1 second, 2 seconds, 4 seconds.

        let delay: Double = pow(
            2.0,
            Double(recoveryAttempts - 1)
        )

        let currentGeneration = generation

        recoveryTask = Task { @MainActor [weak self] in

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard let self,
                  self.generation == currentGeneration,
                  self.session == nil else {
                return
            }

            self.recoveryTask = nil
            self.installNewSession()
        }
    }

    // MARK: - Stop

    func stop() {

        generation &+= 1

        measurementTimeoutTask?.cancel()
        measurementTimeoutTask = nil

        recoveryTask?.cancel()
        recoveryTask = nil

        let oldSession = session
        session = nil

        oldSession?.delegate = nil
        oldSession?.invalidate()

        peerConfiguration = nil

        isRunning = false
        isSuspended = false

        recoveryAttempts = 0

        clearMeasurement()

        errorMessage = nil
    }
}

// MARK: - NISessionDelegate

extension NearbyInteractionManager: NISessionDelegate {

    // MARK: - New Measurements

    nonisolated func session(
        _ session: NISession,
        didUpdate nearbyObjects: [NINearbyObject]
    ) {

        let object = nearbyObjects.first

        let newDistance = object?.distance
        let newDirection = object?.direction

        Task { @MainActor in

            guard self.session === session else {
                return
            }

            self.receiveMeasurement(
                distance: newDistance,
                direction: newDirection
            )
        }
    }

    // MARK: - Session Invalidated

    nonisolated func session(
        _ session: NISession,
        didInvalidateWith error: Error
    ) {

        Task { @MainActor in

            guard self.session === session else {
                return
            }

            self.invalidateCurrentSession(
                with: error
            )
        }
    }

    // MARK: - Session Suspended

    nonisolated func sessionWasSuspended(
        _ session: NISession
    ) {

        Task { @MainActor in

            guard self.session === session else {
                return
            }

            self.isSuspended = true
            self.isRunning = false

            self.measurementTimeoutTask?.cancel()
            self.measurementTimeoutTask = nil

            self.clearMeasurement()
        }
    }

    // MARK: - Suspension Ended

    nonisolated func sessionSuspensionEnded(
        _ session: NISession
    ) {

        Task { @MainActor in

            guard self.session === session else {
                return
            }

            self.isSuspended = false

            guard let configuration = self.peerConfiguration else {
                return
            }

            session.run(configuration)

            self.isRunning = true
            self.clearMeasurement()
        }
    }
}
