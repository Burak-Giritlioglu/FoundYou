
import SwiftUI

struct ContentView: View {

    // MARK: - Managers

    @StateObject private var pairing = PairingManager()
    @StateObject private var tracking = TrackingCoordinator()

    // MARK: - Connection Shutdown

    @State private var isEndingRequest = false
    @State private var endConnectionError: String?

    // MARK: - Screen State

    private var isWaitingForApproval: Bool {
        pairing.session?.status == .pending &&
        !pairing.isHost
    }

    private var isConnectionBusy: Bool {
        pairing.isLoading ||
        isEndingRequest ||
        tracking.isEndingConnection
    }

    // MARK: - Main View

    var body: some View {
        ZStack {
            FoundYouTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    screenContent
                    trackingErrors
                }
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .onChange(
            of: pairing.isConnected,
            initial: true
        ) { _, connected in

            if connected,
               let session = pairing.session {

                // Connect to the finding state only.
                // Do not start GPS or UWB here.
                tracking.connect(session: session)

            } else {

                // Stop sensors and disconnect finding state.
                tracking.disconnect()

                if !isEndingRequest {
                    endConnectionError = nil
                }
            }
        }
    }

    // MARK: - Safe Connection Shutdown

    private func endConnection() {

        guard pairing.isConnected,
              !isEndingRequest,
              !tracking.isEndingConnection,
              !pairing.isLoading else {
            return
        }

        isEndingRequest = true
        endConnectionError = nil

        Task { @MainActor in

            defer {
                isEndingRequest = false
            }

            do {

                // Step 1:
                // Stop outgoing GPS uploads and
                // remove our shared GPS location.
                //
                // The pairing session must still
                // be connected at this point.

                try await tracking.prepareForEndConnection()

                // Step 2:
                // End the Firebase pairing session
                // only after GPS cleanup succeeds.

                try await pairing.endPairingAndWait()

                // Step 3:
                // The existing session listener
                // will observe the "ended" status.
                //
                // ContentView's onChange handler
                // will then call tracking.disconnect().

            } catch {

                // Restore the tracking state if
                // the session is still connected.

                if pairing.isConnected {
                    tracking.cancelEndConnection()

                    endConnectionError =
                        error.localizedDescription
                }
            }
        }
    }

    // MARK: - Screen Routing

    @ViewBuilder
    private var screenContent: some View {

        if pairing.isConnected {

            if tracking.hasFoundFriend {

                FoundYouSuccessView(
                    isLoading: isConnectionBusy,
                    onFindAgain: {
                        guard !isConnectionBusy else {
                            return
                        }

                        tracking.startFinding()
                    },
                    onEndConnection: {
                        endConnection()
                    }
                )

            } else if tracking.isFinding {

                findingScreen

            } else {

                ConnectedView(
                    isReady: tracking.isConnected &&
                        !tracking.finding.isUpdating &&
                        !isConnectionBusy,
                    isLoading: isConnectionBusy,
                    onFind: {
                        guard !isConnectionBusy else {
                            return
                        }

                        tracking.startFinding()
                    },
                    onEndConnection: {
                        endConnection()
                    }
                )
            }

        } else if pairing.hasIncomingRequest {

            IncomingRequestView(
                isLoading: pairing.isLoading,
                errorMessage: pairing.errorMessage,
                onAccept: {
                    pairing.acceptPairing()
                },
                onReject: {
                    pairing.rejectPairing()
                }
            )

        } else if isWaitingForApproval {

            WaitingApprovalView(
                errorMessage: pairing.errorMessage
            )

        } else if pairing.session?.status == .ended {

            ConnectionEndedView(
                onFindAgain: {
                    pairing.resetLocalSession()
                    endConnectionError = nil
                }
            )

        } else {

            PairingView(pairing: pairing)
        }
    }

    // MARK: - Finding Screen

    private var findingScreen: some View {

        VStack(spacing: 14) {

            NavigationScreen(
                navigation: tracking.navigation,
                deviceQuaternion: tracking.deviceQuaternion,
                isLoading: isConnectionBusy,
                onEndConnection: {
                    endConnection()
                }
            )

            Button {

                guard !isConnectionBusy else {
                    return
                }

                // Stop only the active search.
                // Keep the pairing connection.
                tracking.stopFinding()

            } label: {

                Label(
                    "Stop Finding",
                    systemImage: "pause.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    FoundYouTheme.purple.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            .buttonStyle(.plain)
            .disabled(isConnectionBusy)
            .opacity(isConnectionBusy ? 0.5 : 1)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack(spacing: 9) {

            Image(systemName: "location.north.fill")
                .font(
                    .system(
                        size: 23,
                        weight: .black
                    )
                )
                .foregroundStyle(FoundYouTheme.lime)
                .rotationEffect(.degrees(-25))

            HStack(spacing: 0) {

                Text("Found")
                    .foregroundStyle(.white)

                Text("You")
                    .foregroundStyle(FoundYouTheme.lime)
            }
            .font(
                .system(
                    size: 26,
                    weight: .heavy,
                    design: .rounded
                )
            )

            Spacer()

            Text("FIND YOUR PEOPLE")
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .tracking(1)
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    // MARK: - Errors

    @ViewBuilder
    private var trackingErrors: some View {

        if pairing.isConnected {

            if let error = endConnectionError {
                errorText(
                    source: "CONNECTION",
                    message: error
                )
            }

            if let error = pairing.errorMessage {
                errorText(
                    source: "CONNECTION",
                    message: error
                )
            }

            if let error = tracking.findingError {
                errorText(
                    source: "FINDING",
                    message: error
                )
            }

            if tracking.isTracking {

                if let error = tracking.locationError {
                    errorText(
                        source: "DEVICE GPS",
                        message: error
                    )
                }

                if let error = tracking.liveError {
                    errorText(
                        source: "LOCATION SHARING",
                        message: error
                    )
                }

                if let error = tracking.nearbyError {
                    errorText(
                        source: "UWB RANGING",
                        message: error
                    )
                }

                if let error = tracking.tokenError {
                    errorText(
                        source: "UWB CONNECTION",
                        message: error
                    )
                }
            }
        }
    }

    // MARK: - Error View

    private func errorText(
        source: String,
        message: String
    ) -> some View {

        VStack(spacing: 5) {

            Text(source)
                .font(
                    .system(
                        size: 10,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .tracking(1.2)
                .foregroundStyle(FoundYouTheme.lime)

            Text(message)
                .font(.caption)
                .foregroundStyle(FoundYouTheme.pink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
}
