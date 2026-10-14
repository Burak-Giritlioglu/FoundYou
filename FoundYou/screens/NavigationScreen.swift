import SwiftUI
import simd

struct NavigationScreen: View {

    @ObservedObject var navigation: NavigationManager

    let deviceQuaternion: simd_quatd
    let isLoading: Bool
    let onEndConnection: () -> Void

    var body: some View {
        VStack(spacing: 24) {

            header

            arrowSection

            distanceSection

            connectionStatus

            #if DEBUG
            sensorIndicator
            #endif

            endConnectionButton
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
                    FoundYouTheme.purple.opacity(0.35),
                    lineWidth: 1
                )
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(FoundYouTheme.lime)

                Text("The hunt is on!")
                    .font(
                        .system(
                            size: 25,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Image(systemName: "sparkles")
                    .foregroundStyle(FoundYouTheme.pink)
            }

            Text("Follow the arrow to your friend.")
                .font(.subheadline)
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - 3D Arrow

    private var arrowSection: some View {
        ZStack {

            Circle()
                .stroke(
                    FoundYouTheme.purple.opacity(0.18),
                    lineWidth: 2
                )
                .frame(width: 290, height: 290)

            Circle()
                .stroke(
                    FoundYouTheme.pink.opacity(0.25),
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [7, 12]
                    )
                )
                .frame(width: 230, height: 230)

            Circle()
                .fill(
                    FoundYouTheme.lime.opacity(0.07)
                )
                .frame(width: 190, height: 190)
                .blur(radius: 28)

            if let bearing = navigation.bearing {
                Arrow3DView(
                    orientation: deviceQuaternion,
                    targetBearing: bearing
                )
                .frame(height: 330)

            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(FoundYouTheme.lime)
                        .scaleEffect(1.6)

                    Text("Finding your friend's direction...")
                        .font(.caption)
                        .foregroundStyle(
                            FoundYouTheme.secondaryText
                        )
                }
                .frame(height: 330)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 330)
        .clipped()
    }

    // MARK: - Distance

    private var distanceSection: some View {
        VStack(spacing: 10) {

            if let distance = navigation.distance {
                Text(distanceText(distance))
                    .font(
                        .system(
                            size: 43,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(FoundYouTheme.lime)
                    .contentTransition(.numericText())
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: distance
                    )

            } else {
                Text("Calculating distance...")
                    .font(.subheadline)
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
            }

            HStack(spacing: 7) {
                Image(systemName: "location.fill")
                    .foregroundStyle(FoundYouTheme.pink)

                Text("Getting closer?")
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: - Connection

    private var connectionStatus: some View {
        HStack(spacing: 9) {

            Circle()
                .fill(FoundYouTheme.lime)
                .frame(width: 9, height: 9)

            Text("You're connected!")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FoundYouTheme.lime)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 11)
        .background(
            FoundYouTheme.lime.opacity(0.10),
            in: Capsule()
        )
    }

    // MARK: - Sensor Debug

    #if DEBUG
    private var sensorIndicator: some View {
        HStack(spacing: 8) {

            Circle()
                .fill(
                    navigation.source == .uwb
                        ? FoundYouTheme.lime
                        : FoundYouTheme.pink
                )
                .frame(width: 8, height: 8)

            Text(
                navigation.source == .uwb
                    ? "UWB TEST"
                    : navigation.source == .gps
                        ? "GPS"
                        : "WAITING FOR DIRECTION"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(
                FoundYouTheme.secondaryText
            )
        }
        .padding(.vertical, 6)
    }
    #endif

    // MARK: - End Connection

    private var endConnectionButton: some View {
        Button(action: onEndConnection) {
            HStack(spacing: 9) {
                Image(systemName: "xmark.circle.fill")

                Text("End connection")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(FoundYouTheme.pink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                FoundYouTheme.pink.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        FoundYouTheme.pink.opacity(0.35),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Distance Formatting

    private func distanceText(_ distance: Double) -> String {
        if distance < 1000 {
            return String(format: "%.1f m", distance)
        }

        return String(
            format: "%.2f km",
            distance / 1000
        )
    }
}
