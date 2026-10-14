
import SwiftUI

enum FoundYouTheme {

    // Backgrounds
    static let background = Color(
        red: 0.055,
        green: 0.035,
        blue: 0.14
    )

    static let card = Color(
        red: 0.13,
        green: 0.08,
        blue: 0.29
    )

    // Playful Neon palette
    static let lime = Color(
        red: 0.75,
        green: 1.0,
        blue: 0.36
    )

    static let pink = Color(
        red: 1.0,
        green: 0.30,
        blue: 0.75
    )

    static let purple = Color(
        red: 0.54,
        green: 0.25,
        blue: 1.0
    )

    static let blue = Color(
        red: 0.25,
        green: 0.60,
        blue: 1.0
    )

    static let primaryText = Color.white

    static let secondaryText = Color(
        red: 0.73,
        green: 0.70,
        blue: 0.85
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            background,
            Color(
                red: 0.10,
                green: 0.05,
                blue: 0.25
            ),
            background
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [
            card,
            Color(
                red: 0.19,
                green: 0.09,
                blue: 0.38
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
