import SwiftUI
import UIKit

struct PairingCodeCard: View {

    let code: String
    let expiresAt: Date
    let onGenerateNewCode: () -> Void

    @State private var copied = false

    private var digits: [String] {
        code.map { String($0) }
    }

    var body: some View {
        VStack(spacing: 20) {

            header

            codeDisplay

            countdown

            shareButton

            copyButton

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            Button(action: onGenerateNewCode) {
                Label(
                    "Generate a new code",
                    systemImage: "arrow.clockwise"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            FoundYouTheme.cardGradient,
            in: RoundedRectangle(cornerRadius: 26)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(
                    FoundYouTheme.purple.opacity(0.5),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your secret code")
                    .font(
                        .system(
                            size: 22,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Text("Send it to your favorite person ✨")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        FoundYouTheme.secondaryText
                    )
            }

            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundStyle(FoundYouTheme.lime)
        }
    }

    // MARK: - Code Display

    private var codeDisplay: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { index in
                Text(
                    index < digits.count
                        ? digits[index]
                        : ""
                )
                .font(
                    .system(
                        size: 29,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(FoundYouTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    Color.white,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Secret code: \(code)")
    }

    // MARK: - Countdown

    private var countdown: some View {
        TimelineView(
            .periodic(from: .now, by: 1)
        ) { context in

            let seconds = max(
                0,
                Int(
                    ceil(
                        expiresAt.timeIntervalSince(
                            context.date
                        )
                    )
                )
            )

            HStack(spacing: 7) {
                Image(systemName: "clock")

                Text(
                    seconds > 0
                        ? String(
                            format: "Expires in %02d:%02d",
                            seconds / 60,
                            seconds % 60
                        )
                        : "Code expired"
                )
            }
            .font(
                .system(
                    size: 12,
                    weight: .semibold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                seconds > 0
                    ? FoundYouTheme.lime
                    : FoundYouTheme.pink
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                .white.opacity(0.08),
                in: Capsule()
            )
        }
    }

    // MARK: - Share

    private var shareButton: some View {
        ShareLink(
            item: """
            ✨ Come find me on FoundYou!

            My secret code: \(code)

            Open FoundYou and enter the code to connect.
            The code expires in 5 minutes.
            """
        ) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")

                Text("Share the magic")
                    .font(
                        .system(
                            size: 16,
                            weight: .bold,
                            design: .rounded
                        )
                    )
            }
            .foregroundStyle(FoundYouTheme.background)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                FoundYouTheme.lime,
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copy

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true

            UIImpactFeedbackGenerator(
                style: .light
            ).impactOccurred()

        } label: {
            HStack(spacing: 8) {
                Image(
                    systemName: copied
                        ? "checkmark.circle.fill"
                        : "doc.on.doc"
                )

                Text(
                    copied
                        ? "Copied!"
                        : "Copy code"
                )
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .onChange(of: code) { _, _ in
            copied = false
        }
    }
}
