import SwiftUI

struct ConnectionEndedView: View {

    let onFindAgain: () -> Void

    @State private var animate = false

    var body: some View {
        VStack(spacing: 24) {

            illustration

            VStack(spacing: 12) {
                Text("See you soon!")
                    .font(
                        .system(
                            size: 32,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Text("The connection has ended,\nbut the adventure isn't over!")
                    .font(.subheadline)
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
                    .multilineTextAlignment(.center)
            }

            Button(action: onFindAgain) {
                HStack(spacing: 10) {
                    Image(systemName: "location.north.fill")

                    Text("Find someone again")
                        .font(
                            .system(
                                size: 16,
                                weight: .bold,
                                design: .rounded
                            )
                        )

                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(FoundYouTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    FoundYouTheme.lime,
                    in: RoundedRectangle(cornerRadius: 18)
                )
            }
            .buttonStyle(.plain)

            Label(
                "Until the next adventure!",
                systemImage: "sparkles"
            )
            .font(.caption)
            .foregroundStyle(
                FoundYouTheme.secondaryText
            )
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(
            FoundYouTheme.cardGradient,
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    FoundYouTheme.purple.opacity(0.4),
                    lineWidth: 1
                )
        }
        .padding(.horizontal, 24)
        .onAppear {
            animate = true
        }
        .onDisappear {
            animate = false
        }
    }

    // MARK: - Illustration

    private var illustration: some View {
        ZStack {

            Circle()
                .fill(
                    FoundYouTheme.purple.opacity(0.15)
                )
                .frame(width: 215, height: 215)

            Circle()
                .stroke(
                    FoundYouTheme.purple.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 185, height: 185)

            Circle()
                .stroke(
                    FoundYouTheme.pink.opacity(0.45),
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [6, 12]
                    )
                )
                .frame(width: 210, height: 210)

            Image(systemName: "heart.fill")
                .font(.system(size: 86))
                .foregroundStyle(FoundYouTheme.pink)
                .shadow(
                    color: FoundYouTheme.pink.opacity(0.45),
                    radius: 25
                )
                .scaleEffect(animate ? 1.05 : 0.88)
                .animation(
                    .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                    value: animate
                )

            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundStyle(FoundYouTheme.lime)
                .offset(x: 90, y: -70)

            Image(systemName: "sparkle")
                .font(.system(size: 19))
                .foregroundStyle(FoundYouTheme.pink)
                .offset(x: -90, y: 65)

            Image(systemName: "star.fill")
                .font(.system(size: 13))
                .foregroundStyle(FoundYouTheme.lime)
                .offset(x: -75, y: -82)
        }
        .frame(height: 235)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        FoundYouTheme.backgroundGradient
            .ignoresSafeArea()

        ConnectionEndedView(onFindAgain: {})
    }
    .preferredColorScheme(.dark)
}
