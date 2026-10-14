import SwiftUI

struct WaitingApprovalView: View {

    let errorMessage: String?

    @State private var animate = false

    var body: some View {
        VStack(spacing: 26) {

            illustration

            VStack(spacing: 12) {

                Text("Almost connected!")
                    .font(
                        .system(
                            size: 30,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(
                    "Your request is on its way.\nWaiting for your friend to let you in!"
                )
                .font(.subheadline)
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
                .multilineTextAlignment(.center)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            HStack(spacing: 10) {
                ProgressView()
                    .tint(FoundYouTheme.lime)

                Text("WAITING FOR APPROVAL")
                    .font(
                        .system(
                            size: 11,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .tracking(1.5)
                    .foregroundStyle(FoundYouTheme.lime)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                FoundYouTheme.lime.opacity(0.10),
                in: Capsule()
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(FoundYouTheme.pink)
                    .multilineTextAlignment(.center)
            }

            Label(
                "The adventure starts when you're both connected.",
                systemImage: "sparkles"
            )
            .font(.caption)
            .foregroundStyle(
                FoundYouTheme.secondaryText
            )
            .multilineTextAlignment(.center)
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
                    FoundYouTheme.purple.opacity(0.40),
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
                    FoundYouTheme.purple.opacity(0.13)
                )
                .frame(width: 230, height: 230)

            Circle()
                .stroke(
                    FoundYouTheme.purple.opacity(0.35),
                    lineWidth: 2
                )
                .frame(width: 190, height: 190)

            Circle()
                .stroke(
                    FoundYouTheme.pink.opacity(0.55),
                    style: StrokeStyle(
                        lineWidth: 3,
                        dash: [7, 12]
                    )
                )
                .frame(width: 210, height: 210)
                .rotationEffect(
                    .degrees(animate ? 45 : 0)
                )
                .animation(
                    .easeInOut(duration: 3)
                        .repeatForever(autoreverses: true),
                    value: animate
                )

            HStack(spacing: 12) {

                personBubble(
                    icon: "person.fill",
                    color: FoundYouTheme.lime
                )
                .offset(y: animate ? -7 : 5)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        FoundYouTheme.pink
                    )
                    .scaleEffect(animate ? 1.2 : 0.8)

                personBubble(
                    icon: "person.fill",
                    color: FoundYouTheme.pink
                )
                .offset(y: animate ? 7 : -5)
            }
            .animation(
                .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                value: animate
            )

            Image(systemName: "sparkle")
                .font(.system(size: 24))
                .foregroundStyle(FoundYouTheme.lime)
                .offset(x: 95, y: -65)

            Image(systemName: "sparkle")
                .font(.system(size: 16))
                .foregroundStyle(FoundYouTheme.pink)
                .offset(x: -93, y: 73)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: - Person Bubble

    private func personBubble(
        icon: String,
        color: Color
    ) -> some View {
        ZStack {

            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 70, height: 70)

            Circle()
                .stroke(
                    color.opacity(0.6),
                    lineWidth: 2
                )
                .frame(width: 70, height: 70)

            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(color)
        }
    }
}
