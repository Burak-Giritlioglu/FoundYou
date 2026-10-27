
import Foundation
import Combine
import Security
import FirebaseAuth
import FirebaseDatabase

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

    // MARK: - Published State

    @Published private(set) var session: PairingSession?
    @Published private(set) var pairingCode: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Firebase

    private let db = Database.database(
        url: "https://foundyou-5a965-default-rtdb.europe-west1.firebasedatabase.app"
    )

    private var observedReference: DatabaseReference?
    private var observerHandle: DatabaseHandle?

    var currentUID: String? {
        Auth.auth().currentUser?.uid
    }

    var isConnected: Bool {
        session?.status == .connected
    }

    var isHost: Bool {
        session?.hostUID == currentUID
    }

    var hasIncomingRequest: Bool {
        isHost && session?.status == .pending
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    private func reference(_ code: String) -> DatabaseReference {
        db.reference()
            .child("sessions")
            .child(code)
    }

    private func createCode() throws -> String {
        var number: UInt32 = 0

        let result = withUnsafeMutableBytes(of: &number) {
            SecRandomCopyBytes(
                kSecRandomDefault,
                $0.count,
                $0.baseAddress!
            )
        }

        guard result == errSecSuccess else {
            throw PairingError.randomGenerationFailed
        }

        return String(format: "%06d", number % 1_000_000)
    }

    private func decode(
        code: String,
        data: [String: Any]
    ) -> PairingSession? {

        guard let hostUID = data["hostUID"] as? String,
              let statusString = data["status"] as? String,
              let status = PairingStatus(rawValue: statusString),
              let createdAt = data["createdAt"] as? NSNumber,
              let expiresAt = data["expiresAt"] as? NSNumber else {
            return nil
        }

        return PairingSession(
            id: code,
            hostUID: hostUID,
            guestUID: data["guestUID"] as? String,
            status: status,
            createdAt: Date(
                timeIntervalSince1970: createdAt.doubleValue / 1000
            ),
            expiresAt: Date(
                timeIntervalSince1970: expiresAt.doubleValue / 1000
            )
        )
    }

    // MARK: - Create Connection

    func preparePairing() {
        guard !isLoading else { return }

        Task {
            await createPairing()
        }
    }

    private func createPairing() async {

        guard let uid = currentUID else {
            errorMessage = "Authentication is not ready."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            for _ in 0..<5 {
                let code = try createCode()
                let now = Date()
                let expiry = now.addingTimeInterval(300)

                let data: [String: Any] = [
                    "hostUID": uid,
                    "status": PairingStatus.waiting.rawValue,
                    "createdAt": Int64(now.timeIntervalSince1970 * 1000),
                    "expiresAt": Int64(expiry.timeIntervalSince1970 * 1000)
                ]

                let created = try await transaction(
                    at: reference(code)
                ) { existing in
                    guard existing == nil else { return nil }
                    return data
                }

                guard created else { continue }

                pairingCode = code
                session = PairingSession(
                    id: code,
                    hostUID: uid,
                    guestUID: nil,
                    status: .waiting,
                    createdAt: now,
                    expiresAt: expiry
                )

                listen(code: code)
                return
            }

            errorMessage = "Could not generate an available code."

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Join Connection

    func joinPairing(code: String) {
        guard !isLoading else { return }

        Task {
            await requestPairing(code: code)
        }
    }

    private func requestPairing(code: String) async {

        guard let uid = currentUID else {
            errorMessage = "Authentication is not ready."
            return
        }

        let code = code.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard code.count == 6,
              code.allSatisfy({ $0.isNumber }) else {
            errorMessage = "Enter a valid 6-digit code."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let ref = reference(code)

            let joined = try await transaction(at: ref) { existing in
                guard var data = existing,
                      let hostUID = data["hostUID"] as? String,
                      hostUID != uid,
                      let status = data["status"] as? String,
                      status == PairingStatus.waiting.rawValue,
                      data["guestUID"] == nil,
                      let expiresAt = data["expiresAt"] as? NSNumber,
                      expiresAt.doubleValue >
                        Date().timeIntervalSince1970 * 1000 else {
                    return nil
                }

                data["guestUID"] = uid
                data["status"] = PairingStatus.pending.rawValue
                return data
            }

            guard joined else {
                errorMessage = "Code is invalid, expired, or already used."
                return
            }

            let snapshot = try await ref.getData()

            guard let data = snapshot.value as? [String: Any],
                  let updatedSession = decode(
                    code: code,
                    data: data
                  ) else {
                errorMessage = "Could not load the connection."
                return
            }

            pairingCode = nil
            session = updatedSession
            listen(code: code)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Accept / Reject / End

    func acceptPairing() {
        guard hasIncomingRequest,
              let code = session?.id else { return }

        Task {
            await changeStatus(code: code, to: .connected)
        }
    }

    func rejectPairing() {
        guard hasIncomingRequest,
              let code = session?.id else { return }

        Task {
            await changeStatus(code: code, to: .ended)
        }
    }

    func endPairing() {
        guard session?.status == .connected,
              let code = session?.id else { return }

        Task {
            await changeStatus(code: code, to: .ended)
        }
    }

    // MARK: - Awaitable End Connection

    // NEW:
    // Call after TrackingCoordinator has
    // successfully cleaned up local GPS sharing.

    func endPairingAndWait() async throws {

        guard session?.status == .connected,
              let code = session?.id else {
            throw PairingEndError.notConnected
        }

        guard !isLoading else {
            throw PairingEndError.operationInProgress
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                reference(code).updateChildValues([
                    "status": PairingStatus.ended.rawValue
                ]) { error, _ in

                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func changeStatus(
        code: String,
        to newStatus: PairingStatus
    ) async {

        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                reference(code).updateChildValues([
                    "status": newStatus.rawValue
                ]) { error, _ in

                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Session Listener

    private func listen(code: String) {
        stopListening()

        let ref = reference(code)
        observedReference = ref

        observerHandle = ref.observe(
            .value,
            with: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.observedReference?.key == code,
                          let data = snapshot.value as? [String: Any],
                          let updated = self.decode(
                            code: code,
                            data: data
                          ) else {
                        return
                    }

                    self.session = updated

                    if updated.status == .ended {
                        self.pairingCode = nil
                    }

                    print(
                        "RTDB SESSION:",
                        code,
                        updated.status.rawValue
                    )
                }
            },
            withCancel: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func stopListening() {
        if let ref = observedReference,
           let handle = observerHandle {
            ref.removeObserver(withHandle: handle)
        }

        observedReference = nil
        observerHandle = nil
    }

    // MARK: - Atomic Transaction

    private func transaction(
        at ref: DatabaseReference,
        change: @escaping ([String: Any]?) -> [String: Any]?
    ) async throws -> Bool {

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, Error>) in

            ref.runTransactionBlock({ currentData in
                let existing = currentData.value as? [String: Any]

                guard let updated = change(existing) else {
                    return TransactionResult.abort()
                }

                currentData.value = updated
                return TransactionResult.success(
                    withValue: currentData
                )

            }, andCompletionBlock: { error, committed, _ in

                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: committed)
                }

            }, withLocalEvents: false)
        }
    }

    // MARK: - Cleanup

    func resetLocalSession() {
        stopListening()
        session = nil
        pairingCode = nil
        errorMessage = nil
    }

    deinit {
        if let ref = observedReference,
           let handle = observerHandle {
            ref.removeObserver(withHandle: handle)
        }
    }
}

enum PairingError: LocalizedError {
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Could not generate a secure connection code."
        }
    }
}

// MARK: - Connection End Errors

enum PairingEndError: LocalizedError {
    case notConnected
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No active connection to end."
        case .operationInProgress:
            return "Another connection operation is in progress."
        }
    }
}
