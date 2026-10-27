
import SwiftUI
import simd

struct NavigationScreen: View {

    @ObservedObject var navigation: NavigationManager

    let deviceQuaternion: simd_quatd
    let isLoading: Bool
    let onEndConnection: () -> Void

    @AppStorage("selectedArrowColor")
    private var selectedArrowColor =
        ArrowColor.lime.rawValue

    @State private var showColorPicker = false

    // MARK: - Color

    private var currentArrowColor: ArrowColor {
        ArrowColor(rawValue: selectedArrowColor) ?? .lime
    }

    private var arrowColorBinding: Binding<ArrowColor> {
        Binding(
            get: {
                currentArrowColor
            },
            set: { newColor in
                selectedArrowColor = newColor.rawValue
            }
        )
    }

    // MARK: - Arrow Availability

    private var hasArrowDirection: Bool {
        navigation.uwbArrowDirection != nil ||
        navigation.bearing != nil
    }

    // MARK: - Friend GPS Status

    private var showLastKnownLocation: Bool {
        navigation.source == .gps &&
        navigation.isFriendLocationLastKnown &&
        navigation.friendLocationUpdatedAt != nil
    }

    private var lastUpdatedText: String? {

        guard let date = navigation.friendLocationUpdatedAt else {
            return nil
        }

        let seconds = max(
            Int(Date().timeIntervalSince(date)),
            0
        )

        if seconds < 60 {
            return "Updated less than a minute ago"
        }

        let minutes = seconds / 60

        if minutes < 60 {
            return "Last updated \(minutes) min ago"
        }

        let hours = minutes / 60

        if hours < 24 {
            return "Last updated \(hours) hr ago"
        }

        let days = hours / 24

        return "Last updated \(days) days ago"
    }

    // MARK: - Main View

    var body: some View {

        VStack(spacing: 16) {

            navigationCard

            customizationSection
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Navigation Card

    private var navigationCard: some View {

        VStack(spacing: 22) {

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
                    currentArrowColor.color.opacity(0.18),
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
                    currentArrowColor.color.opacity(0.07)
                )
                .frame(width: 190, height: 190)
                .blur(radius: 28)

            if hasArrowDirection {

                Arrow3DView(
                    orientation: deviceQuaternion,
                    targetBearing: navigation.bearing ?? 0,
                    uwbDirection: navigation.uwbArrowDirection,
                    arrowColor: currentArrowColor
                )
                .frame(height: 330)
                .opacity(
                    navigation.isMeasurementStale
                        ? 0.55
                        : 1
                )

            } else {

                VStack(spacing: 16) {

                    ProgressView()
                        .tint(currentArrowColor.color)
                        .scaleEffect(1.6)

                    Text(
                        navigation.distance != nil
                        ? "Distance found. Waiting for direction..."
                        : "Finding your friend's direction..."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
                    .multilineTextAlignment(.center)
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
                    .foregroundStyle(currentArrowColor.color)
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

            // MARK: Last Known GPS Location

            if showLastKnownLocation {

                VStack(spacing: 6) {

                    HStack(spacing: 7) {

                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(FoundYouTheme.pink)

                        Text("Last known location")
                            .font(
                                .system(
                                    size: 13,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.white)
                    }

                    if let updatedText = lastUpdatedText {

                        Text(updatedText)
                            .font(.caption2)
                            .foregroundStyle(
                                FoundYouTheme.secondaryText
                            )
                    }

                    Text("Your friend may have moved.")
                        .font(.caption2)
                        .foregroundStyle(
                            FoundYouTheme.secondaryText
                        )
                }
                .multilineTextAlignment(.center)

            } else if navigation.isMeasurementStale {

                Text("Last known measurement")
                    .font(.caption2)
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )

            } else {

                HStack(spacing: 7) {

                    Image(systemName: "location.fill")
                        .foregroundStyle(FoundYouTheme.pink)

                    Text("Follow the arrow!")
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
    }

    // MARK: - Connection

    private var connectionStatus: some View {

        HStack(spacing: 9) {

            Circle()
                .fill(FoundYouTheme.lime)
                .frame(width: 9, height: 9)

            Text("You're connected!")
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
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
                    navigation.uwbArrowDirection != nil
                        ? FoundYouTheme.lime
                        : FoundYouTheme.pink
                )
                .frame(width: 8, height: 8)

            Text(sensorText)
                .font(.caption2.monospaced())
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
        }
        .padding(.vertical, 6)
    }

    private var sensorText: String {

        if navigation.uwbArrowDirection != nil {
            return "UWB 3D DIRECTION"
        }

        if navigation.source == .uwb {
            return navigation.bearing != nil
                ? "UWB DISTANCE + GPS DIRECTION"
                : "UWB DISTANCE ONLY"
        }

        if navigation.source == .gps {
            return navigation.isFriendLocationLastKnown
                ? "GPS LAST KNOWN LOCATION"
                : "GPS"
        }

        return navigation.bearing != nil
            ? "LAST KNOWN DIRECTION"
            : "WAITING FOR DIRECTION"
    }
    #endif

    // MARK: - Customization

    private var customizationSection: some View {

        VStack(spacing: 12) {

            Button {

                withAnimation(.spring(response: 0.3)) {
                    showColorPicker.toggle()
                }

            } label: {

                HStack(spacing: 12) {

                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(currentArrowColor.color)

                    Text("Customize your arrow")
                        .font(
                            .system(
                                size: 15,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)

                    Spacer()

                    Circle()
                        .fill(currentArrowColor.color)
                        .frame(width: 22, height: 22)

                    Image(
                        systemName: showColorPicker
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
                }
                .padding(18)
                .background(
                    FoundYouTheme.cardGradient,
                    in: RoundedRectangle(cornerRadius: 20)
                )
            }
            .buttonStyle(.plain)

            if showColorPicker {

                ArrowColorPicker(
                    selectedColor: arrowColorBinding
                )
                .transition(
                    .opacity.combined(
                        with: .move(edge: .top)
                    )
                )
            }
        }
    }

    // MARK: - End Connection

    private var endConnectionButton: some View {

        Button(action: onEndConnection) {

            HStack(spacing: 9) {

                Image(systemName: "xmark.circle.fill")

                Text("End connection")
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
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
            return String(
                format: "%.1f m",
                distance
            )
        }

        return String(
            format: "%.2f km",
            distance / 1000
        )
    }
}
