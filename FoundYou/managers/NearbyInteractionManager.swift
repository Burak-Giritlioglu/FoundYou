import Foundation
import Combine
import NearbyInteraction
import simd

@MainActor
final class NearbyInteractionManager: NSObject, ObservableObject {

    @Published private(set) var isSupported = false
    @Published private(set) var isRunning = false

    @Published private(set) var distance: Float?
    @Published private(set) var direction: SIMD3<Float>?

    @Published private(set) var measurementID: UInt64 = 0
    @Published private(set) var lastMeasurementAt: Date?

    @Published private(set) var errorMessage: String?

    private var session: NISession?
    private var measurementTimeoutTask: Task<Void, Never>?

    private var generation: UInt64 = 0

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

    override init() {
        super.init()

        isSupported = NISession.deviceCapabilities
            .supportsPreciseDistanceMeasurement
    }

    // MARK: - Prepare

    func prepare() {
        guard isSupported else {
            errorMessage = "Bu cihaz UWB desteklemiyor."
            return
        }

        stop()

        let newSession = NISession()
        newSession.delegate = self

        session = newSession
        errorMessage = nil
    }

    // MARK: - Start

    func start(peerTokenData: Data) {
        guard let session else {
            errorMessage = "UWB oturumu hazırlanmadı."
            return
        }

        do {
            guard let token = try NSKeyedUnarchiver
                .unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: peerTokenData
                ) else {
                errorMessage = "Arkadaşın UWB anahtarı okunamadı."
                return
            }

            let configuration = NINearbyPeerConfiguration(
                peerToken: token
            )

            session.run(configuration)

            isRunning = true
            errorMessage = nil

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Measurements

    private func receiveMeasurement(
        distance newDistance: Float?,
        direction newDirection: SIMD3<Float>?
    ) {
        guard isRunning else {
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

        restartMeasurementTimeout()
    }

    private func restartMeasurementTimeout() {
        measurementTimeoutTask?.cancel()

        let currentGeneration = generation

        measurementTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))

            guard !Task.isCancelled,
                  let self,
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

    // MARK: - Stop

    func stop() {
        generation &+= 1

        measurementTimeoutTask?.cancel()
        measurementTimeoutTask = nil

        let oldSession = session
        session = nil

        oldSession?.delegate = nil
        oldSession?.invalidate()

        isRunning = false
        clearMeasurement()
        errorMessage = nil
    }

    private func invalidateCurrentSession(
        with error: Error
    ) {
        generation &+= 1

        measurementTimeoutTask?.cancel()
        measurementTimeoutTask = nil

        session = nil
        isRunning = false

        clearMeasurement()
        errorMessage = error.localizedDescription
    }
}

// MARK: - NISessionDelegate

extension NearbyInteractionManager: NISessionDelegate {

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

    nonisolated func session(
        _ session: NISession,
        didInvalidateWith error: Error
    ) {
        Task { @MainActor in
            guard self.session === session else {
                return
            }

            self.invalidateCurrentSession(with: error)
        }
    }

    nonisolated func sessionWasSuspended(
        _ session: NISession
    ) {
        Task { @MainActor in
            guard self.session === session else {
                return
            }

            self.isRunning = false
            self.measurementTimeoutTask?.cancel()
            self.measurementTimeoutTask = nil
            self.clearMeasurement()
        }
    }

    nonisolated func sessionSuspensionEnded(
        _ session: NISession
    ) {
        Task { @MainActor in
            guard self.session === session else {
                return
            }

            self.isRunning = true
            self.clearMeasurement()
        }
    }
}
