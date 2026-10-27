import SwiftUI

struct ConnectedView: View {

    let isReady: Bool
    let isLoading: Bool
    let onFind: () -> Void
    let onEndConnection: () -> Void

    var body: some View {

        VStack(spacing: 24) {

            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(FoundYouTheme.lime)

            VStack(spacing: 8) {

                Text("You're Connected!")
                    .font(
                        .system(
                            size: 27,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Text("Ready to find your friend?")
                    .font(.subheadline)
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
                    .multilineTextAlignment(.center)
            }

            // MARK: - Find You

            Button(action: onFind) {

                Label(
                    "Find You",
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
            .disabled(!isReady || isLoading)
            .opacity(isReady && !isLoading ? 1 : 0.5)

            Text("Find your friend whenever you're ready.")
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

        ConnectedView(
            isReady: true,
            isLoading: false,
            onFind: {},
            onEndConnection: {}
        )
    }
    .preferredColorScheme(.dark)
}
