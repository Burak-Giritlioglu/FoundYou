
import Foundation
import Combine
import Security
import FirebaseAuth
import FirebaseFirestore

enum PairingStatus: String, Codable {
    case waiting
    case pending
    case connected
    case ended
}

struct PairingSession: Identifiable, Codable {
    var id: String
    var hostUID: String
    var guestUID: String?
    var status: PairingStatus
    var createdAt: Date
    var expiresAt: Date
}

@MainActor
final class PairingManager: ObservableObject {

    @Published private(set) var session: PairingSession?
    @Published private(set) var pairingCode: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()
    private var sessionListener: ListenerRegistration?

    var currentUID: String? {
        Auth.auth().currentUser?.uid
    }

    var isConnected: Bool {
        session?.status == .connected
    }

    var isHost: Bool {
        guard let session, let uid = currentUID else {
            return false
        }
        return session.hostUID == uid
    }

    var hasIncomingRequest: Bool {
        isHost && session?.status == .pending
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Random Code

    private func generatePairingCode() throws -> String {
        var randomNumber: UInt32 = 0

        let result = withUnsafeMutableBytes(of: &randomNumber) {
            SecRandomCopyBytes(
                kSecRandomDefault,
                $0.count,
                $0.baseAddress!
            )
        }

        guard result == errSecSuccess else {
            throw PairingError.randomGenerationFailed
        }

        return String(
            format: "%06d",
            randomNumber % 1_000_000
        )
    }

    // MARK: - Create Pairing

    func preparePairing() {
        guard !isLoading else { return }

        Task {
            await createPairing()
        }
    }

    private func createPairing() async {

        guard let uid = currentUID else {
            errorMessage = "Firebase oturumu henüz açılmadı."
            return
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let code = try generatePairingCode()
            let reference = db
                .collection("pairingCodes")
                .document(code)

            let now = Date()
            let expiry = now.addingTimeInterval(300)

            let data: [String: Any] = [
                "hostUID": uid,
                "status": "waiting",
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": Timestamp(date: expiry)
            ]

            try await reference.setData(data)

            pairingCode = code

            session = PairingSession(
                id: code,
                hostUID: uid,
                guestUID: nil,
                status: .waiting,
                createdAt: now,
                expiresAt: expiry
            )

            listenToSession(code: code)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Join Pairing

    func joinPairing(code: String) {
        guard !isLoading else { return }

        Task {
            await requestPairing(code: code)
        }
    }

    private func requestPairing(code: String) async {

        guard let uid = currentUID else {
            errorMessage = "Firebase oturumu henüz açılmadı."
            return
        }

        guard code.count == 6,
              code.allSatisfy({ $0.isNumber }) else {
            errorMessage = "Geçerli bir 6 haneli kod gir."
            return
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        let reference = db
            .collection("pairingCodes")
            .document(code)

        do {
            let snapshot = try await reference.getDocument()

            guard let data = snapshot.data() else {
                errorMessage = "Eşleştirme kodu bulunamadı."
                return
            }

            guard let hostUID = data["hostUID"] as? String,
                  let status = data["status"] as? String,
                  let expiry = data["expiresAt"] as? Timestamp,
                  let created = data["createdAt"] as? Timestamp else {
                errorMessage = "Eşleştirme verisi geçersiz."
                return
            }

            guard hostUID != uid else {
                errorMessage = "Kendi kodunla eşleşemezsin."
                return
            }

            guard status == "waiting" else {
                errorMessage = "Bu kod artık kullanılabilir değil."
                return
            }

            guard expiry.dateValue() > Date() else {
                errorMessage = "Eşleştirme kodunun süresi dolmuş."
                return
            }

            try await reference.updateData([
                "guestUID": uid,
                "status": "pending"
            ])

            pairingCode = nil

            session = PairingSession(
                id: code,
                hostUID: hostUID,
                guestUID: uid,
                status: .pending,
                createdAt: created.dateValue(),
                expiresAt: expiry.dateValue()
            )

            listenToSession(code: code)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Accept Request

    func acceptPairing() {
        guard hasIncomingRequest,
              let code = session?.id else {
            return
        }

        Task {
            await updateStatus(
                code: code,
                status: .connected
            )
        }
    }

    // MARK: - Reject Request

    func rejectPairing() {
        guard hasIncomingRequest,
              let code = session?.id else {
            return
        }

        Task {
            await updateStatus(
                code: code,
                status: .ended
            )
        }
    }

    // MARK: - End Pairing

    func endPairing() {
        guard let code = session?.id,
              session?.status == .connected else {
            return
        }

        Task {
            await updateStatus(
                code: code,
                status: .ended
            )
        }
    }

    private func updateStatus(
        code: String,
        status: PairingStatus
    ) async {

        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            try await db
                .collection("pairingCodes")
                .document(code)
                .updateData([
                    "status": status.rawValue
                ])

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Realtime Listener

    private func listenToSession(code: String) {

        sessionListener?.remove()
        sessionListener = nil

        sessionListener = db
            .collection("pairingCodes")
            .document(code)
            .addSnapshotListener { [weak self] snapshot, error in

                Task { @MainActor in
                    guard let self else { return }

                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    guard let snapshot,
                          let data = snapshot.data(),
                          let hostUID = data["hostUID"] as? String,
                          let statusString = data["status"] as? String,
                          let status = PairingStatus(
                            rawValue: statusString
                          ),
                          let created = data["createdAt"] as? Timestamp,
                          let expiry = data["expiresAt"] as? Timestamp
                    else {
                        return
                    }

                    self.session = PairingSession(
                        id: code,
                        hostUID: hostUID,
                        guestUID: data["guestUID"] as? String,
                        status: status,
                        createdAt: created.dateValue(),
                        expiresAt: expiry.dateValue()
                    )

                    if status == .ended {
                        self.pairingCode = nil
                    }
                }
            }
    }

    // MARK: - Cleanup

    func resetLocalSession() {
        sessionListener?.remove()
        sessionListener = nil
        session = nil
        pairingCode = nil
        errorMessage = nil
    }

    deinit {
        sessionListener?.remove()
    }
}

enum PairingError: LocalizedError {
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Güvenli eşleştirme kodu oluşturulamadı."
        }
    }
}
