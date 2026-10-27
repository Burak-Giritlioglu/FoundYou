import SwiftUI
import UIKit

enum ArrowColor: String, CaseIterable, Identifiable {

    case lime
    case pink
    case purple
    case blue
    case orange
    case yellow

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .lime: "Lime Rush"
        case .pink: "Candy Pink"
        case .purple: "Electric Purple"
        case .blue: "Ocean Blue"
        case .orange: "Sunset Orange"
        case .yellow: "Sunny Yellow"
        }
    }

    var color: Color {
        Color(uiColor: uiColor)
    }

    var uiColor: UIColor {
        switch self {
        case .lime:
            UIColor(
                red: 0.75,
                green: 1.0,
                blue: 0.36,
                alpha: 1
            )

        case .pink:
            UIColor(
                red: 1.0,
                green: 0.30,
                blue: 0.75,
                alpha: 1
            )

        case .purple:
            UIColor(
                red: 0.54,
                green: 0.25,
                blue: 1.0,
                alpha: 1
            )

        case .blue:
            UIColor(
                red: 0.25,
                green: 0.60,
                blue: 1.0,
                alpha: 1
            )

        case .orange:
            UIColor(
                red: 1.0,
                green: 0.48,
                blue: 0.24,
                alpha: 1
            )

        case .yellow:
            UIColor(
                red: 1.0,
                green: 0.83,
                blue: 0.31,
                alpha: 1
            )
        }
    }
}
