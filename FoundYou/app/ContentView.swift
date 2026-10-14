
import SwiftUI

struct ContentView: View {

    // MARK: - Managers

    @StateObject private var pairing = PairingManager()
    @StateObject private var tracking = TrackingCoordinator()

    // MARK: - Screen State

    private var isWaitingForApproval: Bool {
        pairing.session?.status == .pending &&
        !pairing.isHost
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

                tracking.start(session: session)

            } else {
                tracking.stop()
            }
        }
    }

    // MARK: - Screen Routing

    @ViewBuilder
    private var screenContent: some View {

        if pairing.isConnected {

            NavigationScreen(
                navigation: tracking.navigation,
                deviceQuaternion: tracking.deviceQuaternion,
                isLoading: pairing.isLoading,
                onEndConnection: {
                    pairing.endPairing()
                }
            )

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
                }
            )

        } else {

            PairingView(pairing: pairing)
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

            (
                Text("Found")
                    .foregroundStyle(.white)
                +
                Text("You")
                    .foregroundStyle(FoundYouTheme.lime)
            )
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

    // MARK: - Tracking Errors

    @ViewBuilder
    private var trackingErrors: some View {

        if pairing.isConnected {

            if let error = tracking.locationError {
                errorText(error)
            }

            if let error = tracking.liveError {
                errorText(error)
            }

            if let error = tracking.nearbyError {
                errorText(error)
            }

            if let error = tracking.tokenError {
                errorText(error)
            }
        }
    }

    // MARK: - Helpers

    private func errorText(
        _ message: String
    ) -> some View {

        Text(message)
            .font(.caption)
            .foregroundStyle(
                FoundYouTheme.pink
            )
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
}

#Preview {
    ContentView()
}
