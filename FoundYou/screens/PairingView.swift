
import SwiftUI

struct PairingView: View {

    @ObservedObject var pairing: PairingManager

    @State private var enteredCode = ""
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        VStack(spacing: 24) {

            heroSection

            if let code = pairing.pairingCode,
               let session = pairing.session {

                PairingCodeCard(
                    code: code,
                    expiresAt: session.expiresAt,
                    onGenerateNewCode: {
                        isCodeFocused = false
                        pairing.preparePairing()
                    }
                )

            } else {
                createCodeButton
            }

            joinSection

            privacyMessage

            if pairing.isLoading {
                ProgressView()
                    .tint(FoundYouTheme.lime)
            }

            if let error = pairing.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(FoundYouTheme.pink)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isCodeFocused = false
                }
        }
        .onTapGesture {
            isCodeFocused = false
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {

            ZStack {
                Circle()
                    .stroke(
                        FoundYouTheme.purple.opacity(0.25),
                        lineWidth: 2
                    )
                    .frame(width: 160, height: 160)

                Circle()
                    .stroke(
                        FoundYouTheme.pink.opacity(0.3),
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: [5, 9]
                        )
                    )
                    .frame(width: 125, height: 125)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 70, weight: .black))
                    .foregroundStyle(FoundYouTheme.lime)
                    .rotationEffect(.degrees(-25))
                    .shadow(
                        color: FoundYouTheme.lime.opacity(0.6),
                        radius: 22
                    )

                Image(systemName: "sparkle")
                    .font(.system(size: 23))
                    .foregroundStyle(FoundYouTheme.pink)
                    .offset(x: 80, y: -55)

                Image(systemName: "sparkle")
                    .font(.system(size: 15))
                    .foregroundStyle(FoundYouTheme.lime)
                    .offset(x: -80, y: 45)
            }
            .frame(height: 175)

            Text("Find your\nfavorite people.")
                .font(
                    .system(
                        size: 36,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

            Text("Lost in the crowd? Not anymore. ✨")
                .font(.subheadline)
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    // MARK: - Create Code

    private var createCodeButton: some View {
        Button {
            isCodeFocused = false
            pairing.preparePairing()
        } label: {
            HStack(spacing: 15) {

                Image(systemName: "party.popper.fill")
                    .font(.system(size: 27))
                    .frame(width: 48, height: 48)
                    .background(
                        .black.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text("Create a code")
                        .font(.title3.bold())

                    Text("Invite a friend to find you")
                        .font(.caption)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
            }
            .foregroundStyle(FoundYouTheme.background)
            .padding(18)
            .background(
                FoundYouTheme.lime,
                in: RoundedRectangle(cornerRadius: 22)
            )
        }
        .buttonStyle(.plain)
        .disabled(pairing.isLoading)
    }

    // MARK: - Join Section

    private var joinSection: some View {
        VStack(spacing: 16) {

            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundStyle(FoundYouTheme.pink)

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text("Got a code?")
                        .font(.title3.bold())
                        .foregroundStyle(.white)

                    Text("Your friend is waiting for you!")
                        .font(.caption)
                        .foregroundStyle(
                            FoundYouTheme.secondaryText
                        )
                }

                Spacer()
            }

            TextField(
                "Enter 6-digit code",
                text: $enteredCode
            )
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isCodeFocused)
            .multilineTextAlignment(.center)
            .font(
                .system(
                    size: 23,
                    weight: .bold,
                    design: .monospaced
                )
            )
            .foregroundStyle(.white)
            .tint(FoundYouTheme.lime)
            .padding(15)
            .background(
                .white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .onChange(of: enteredCode) { _, value in
                let filtered = String(
                    value.filter {
                        $0.isASCII && $0.isNumber
                    }
                    .prefix(6)
                )

                if enteredCode != filtered {
                    enteredCode = filtered
                }
            }

            Button {
                isCodeFocused = false
                pairing.joinPairing(code: enteredCode)
            } label: {
                HStack {
                    Spacer()

                    Text("Join the adventure")
                        .font(.headline)

                    Image(systemName: "arrow.right")

                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(
                    FoundYouTheme.pink,
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            .buttonStyle(.plain)
            .disabled(
                enteredCode.count != 6 ||
                pairing.isLoading
            )
        }
        .padding(20)
        .background(
            FoundYouTheme.cardGradient,
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    // MARK: - Privacy

    private var privacyMessage: some View {
        Label(
            "Location is shared only when connected.",
            systemImage: "lock.shield"
        )
        .font(.caption2)
        .foregroundStyle(
            FoundYouTheme.secondaryText
        )
        .multilineTextAlignment(.center)
    }
}
