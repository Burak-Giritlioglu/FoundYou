import SwiftUI

struct IncomingRequestView: View {

    let isLoading: Bool
    let errorMessage: String?
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var animate = false

    var body: some View {
        VStack(spacing: 23) {

            illustration

            VStack(spacing: 10) {
                Text("Someone found you!")
                    .font(
                        .system(
                            size: 29,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("A friend wants to connect.\nReady to find each other?")
                    .font(.subheadline)
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {

                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")

                        Text("Let's connect!")
                            .font(
                                .system(
                                    size: 17,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
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
                .disabled(isLoading)

                Button {
                    onReject()
                } label: {
                    Text("Not now")
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(FoundYouTheme.pink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView()
                    .tint(FoundYouTheme.lime)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(FoundYouTheme.pink)
                    .multilineTextAlignment(.center)
            }

            Label(
                "Only connect with people you trust.",
                systemImage: "lock.shield"
            )
            .font(.caption2)
            .foregroundStyle(
                FoundYouTheme.secondaryText
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            FoundYouTheme.cardGradient,
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    FoundYouTheme.purple.opacity(0.45),
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
                .frame(width: 210, height: 210)

            Circle()
                .stroke(
                    FoundYouTheme.purple.opacity(0.4),
                    lineWidth: 2
                )
                .frame(width: 170, height: 170)

            Circle()
                .stroke(
                    FoundYouTheme.pink.opacity(0.5),
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [6, 10]
                    )
                )
                .frame(width: 205, height: 205)
                .rotationEffect(
                    .degrees(animate ? 30 : 0)
                )
                .animation(
                    .easeInOut(duration: 3)
                        .repeatForever(autoreverses: true),
                    value: animate
                )

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(FoundYouTheme.lime)
                .shadow(
                    color: FoundYouTheme.lime.opacity(0.45),
                    radius: 20
                )

            Image(systemName: "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(FoundYouTheme.pink)
                .offset(x: 70, y: -62)
                .scaleEffect(animate ? 1.15 : 0.85)
                .animation(
                    .easeInOut(duration: 1)
                        .repeatForever(autoreverses: true),
                    value: animate
                )

            Image(systemName: "sparkles")
                .font(.system(size: 23))
                .foregroundStyle(FoundYouTheme.lime)
                .offset(x: -85, y: -55)

            Image(systemName: "sparkle")
                .font(.system(size: 17))
                .foregroundStyle(FoundYouTheme.pink)
                .offset(x: 85, y: 65)
        }
        .frame(height: 225)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
