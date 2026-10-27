import SwiftUI

struct ArrowColorPicker: View {

    @Binding var selectedColor: ArrowColor

    private let columns = [
        GridItem(.adaptive(minimum: 65), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(FoundYouTheme.pink)

                Text("Your arrow, your vibe")
                    .font(
                        .system(
                            size: 18,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "sparkles")
                    .foregroundStyle(FoundYouTheme.lime)
            }

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(ArrowColor.allCases) { arrowColor in
                    colorOption(arrowColor)
                }
            }

            Text("Pick a color that feels like you!")
                .font(.caption)
                .foregroundStyle(
                    FoundYouTheme.secondaryText
                )
        }
        .padding(20)
        .background(
            FoundYouTheme.cardGradient,
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    FoundYouTheme.purple.opacity(0.35),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Color Option

    private func colorOption(
        _ arrowColor: ArrowColor
    ) -> some View {

        let isSelected = selectedColor == arrowColor

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedColor = arrowColor
            }

            UISelectionFeedbackGenerator()
                .selectionChanged()

        } label: {
            VStack(spacing: 8) {

                ZStack {
                    Circle()
                        .fill(arrowColor.color)
                        .frame(width: 45, height: 45)
                        .shadow(
                            color: arrowColor.color.opacity(0.45),
                            radius: isSelected ? 14 : 5
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(
                                FoundYouTheme.background
                            )
                    }
                }
                .padding(5)
                .overlay {
                    Circle()
                        .stroke(
                            isSelected
                                ? Color.white
                                : Color.clear,
                            lineWidth: 2
                        )
                }

                Text(arrowColor.title)
                    .font(
                        .system(
                            size: 10,
                            weight: isSelected
                                ? .bold
                                : .medium
                        )
                    )
                    .foregroundStyle(
                        isSelected
                            ? .white
                            : FoundYouTheme.secondaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(arrowColor.title)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }
}
