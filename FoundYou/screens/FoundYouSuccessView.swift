import SwiftUI

struct FoundYouSuccessView: View {

    let isLoading: Bool
    let onFindAgain: () -> Void
    let onEndConnection: () -> Void

    var body: some View {

        VStack(spacing: 24) {

            // MARK: - Success Icon

            Image(systemName: "party.popper.fill")
                .font(.system(size: 76))
                .foregroundStyle(FoundYouTheme.lime)
                .symbolEffect(.bounce, options: .nonRepeating)

            // MARK: - Success Message

            VStack(spacing: 10) {

                Text("Found You!")
                    .font(
                        .system(
                            size: 36,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Text("You found your friend! 🎉")
                    .font(.subheadline)
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
                    .multilineTextAlignment(.center)
            }

            // MARK: - Find Again

            Button(action: onFindAgain) {

                Label(
                    "Find You Again",
                    systemImage: "location.north.fill"
                )
                .font(
                    .system(
                        size: 18,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    FoundYouTheme.lime,
                    in: RoundedRectangle(cornerRadius: 18)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .opacity(isLoading ? 0.5 : 1)

            // MARK: - Session Information

            Text("Your connection is still active.")
                .font(.caption)
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
                .multilineTextAlignment(.center)

            // MARK: - End Connection

            Button(action: onEndConnection) {

                Text("End Connection")
                    .font(
                        .subheadline.weight(.semibold)
                    )
                    .foregroundStyle(FoundYouTheme.pink)
            }
            .disabled(isLoading)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            FoundYouTheme.cardGradient,
            in: RoundedRectangle(cornerRadius: 28)
        )
        .padding(.horizontal, 24)
    }
}

#Preview {
    ZStack {
        FoundYouTheme.backgroundGradient
            .ignoresSafeArea()

        FoundYouSuccessView(
            isLoading: false,
            onFindAgain: {},
            onEndConnection: {}
        )
    }
    .preferredColorScheme(.dark)
}
