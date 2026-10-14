
import Foundation
import Combine
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class LiveLocationManager: ObservableObject {

    @Published private(set) var friendLocation: CLLocation?
    @Published private(set) var isSharing = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()

    private var friendListener: ListenerRegistration?

    private var activeSessionID: String?
    private var myUID: String?

    private var lastUploadDate: Date?
    private var lastUploadedLocation: CLLocation?

    private var uploadTask: Task<Void, Never>?
    private var generation = 0

    // MARK: - Start

    func start(session: PairingSession) {

        guard session.status == .connected else {
            errorMessage = "Eşleştirme henüz tamamlanmadı."
            return
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Firebase oturumu bulunamadı."
            return
        }

        let otherUID: String

        if session.hostUID == uid {
            guard let guestUID = session.guestUID else {
                errorMessage = "Arkadaşın henüz eşleşmedi."
                return
            }
            otherUID = guestUID

        } else if session.guestUID == uid {
            otherUID = session.hostUID

        } else {
            errorMessage = "Bu oturumun katılımcısı değilsin."
            return
        }

        if isSharing && activeSessionID == session.id {
            return
        }

        stop()

        activeSessionID = session.id
        myUID = uid
        isSharing = true
        errorMessage = nil

        let currentGeneration = generation

        let reference = db
            .collection("liveLocations")
            .document(session.id)
            .collection("users")
            .document(otherUID)

        friendListener = reference.addSnapshotListener {
            [weak self] snapshot, error in

            Task { @MainActor in
                guard let self,
                      self.isSharing,
                      self.generation == currentGeneration,
                      self.activeSessionID == session.id else {
                    return
                }

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = snapshot?.data(),
                      let latitude = data["latitude"] as? Double,
                      let longitude = data["longitude"] as? Double,
                      let accuracy = data["accuracy"] as? Double,
                      let timestamp = data["updatedAt"] as? Timestamp
                else {
                    self.friendLocation = nil
                    return
                }

                let updatedAt = timestamp.dateValue()

                guard abs(updatedAt.timeIntervalSinceNow) < 15 else {
                    self.friendLocation = nil
                    return
                }

                self.friendLocation = CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: latitude,
                        longitude: longitude
                    ),
                    altitude: 0,
                    horizontalAccuracy: accuracy,
                    verticalAccuracy: -1,
                    timestamp: updatedAt
                )
            }
        }
    }

    // MARK: - Upload

    func updateMyLocation(_ location: CLLocation) {

        guard isSharing,
              let sessionID = activeSessionID,
              let uid = myUID,
              uploadTask == nil else {
            return
        }

        guard location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 15 else {
            return
        }

        let now = Date()

        if let lastUploadDate,
           now.timeIntervalSince(lastUploadDate) < 3 {
            return
        }

        if let lastUploadedLocation,
           location.distance(from: lastUploadedLocation) < 2,
           let lastUploadDate,
           now.timeIntervalSince(lastUploadDate) < 10 {
            return
        }

        let currentGeneration = generation

        let reference = db
            .collection("liveLocations")
            .document(sessionID)
            .collection("users")
            .document(uid)

        let data: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        uploadTask = Task { [weak self] in

            guard let self,
                  !Task.isCancelled,
                  self.isSharing,
                  self.generation == currentGeneration,
                  self.activeSessionID == sessionID else {
                return
            }

            do {
                try await reference.setData(data)

                guard !Task.isCancelled,
                      self.isSharing,
                      self.generation == currentGeneration else {
                    return
                }

                self.lastUploadDate = Date()
                self.lastUploadedLocation = location

            } catch {
                guard !Task.isCancelled,
                      self.isSharing,
                      self.generation == currentGeneration else {
                    return
                }

                self.errorMessage = error.localizedDescription
            }

            if self.generation == currentGeneration {
                self.uploadTask = nil
            }
        }
    }

    // MARK: - Stop

    func stop() {

        generation += 1

        uploadTask?.cancel()
        uploadTask = nil

        friendListener?.remove()
        friendListener = nil

        activeSessionID = nil
        myUID = nil

        lastUploadDate = nil
        lastUploadedLocation = nil

        friendLocation = nil
        isSharing = false
        errorMessage = nil
    }

    deinit {
        friendListener?.remove()
        uploadTask?.cancel()
    }
}
