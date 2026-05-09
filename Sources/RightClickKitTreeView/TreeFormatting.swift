import Foundation
import SwiftUI

enum TreeFormatter {
    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "Unknown" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }
}

enum TreePalette {
    static let blue = Color.accentColor
    static let secondaryText = Color.secondary
    static let divider = Color.primary.opacity(0.09)
    static let track = Color.primary.opacity(0.10)
    static let warning = Color(red: 1.0, green: 0.45, blue: 0.32)

    static func depthColor(_ depth: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.30, green: 0.72, blue: 1.0),
            Color(red: 0.28, green: 0.86, blue: 0.54),
            Color(red: 0.93, green: 0.63, blue: 0.24),
            Color(red: 0.82, green: 0.40, blue: 0.96),
            Color(red: 1.00, green: 0.35, blue: 0.50),
            Color(red: 0.42, green: 0.48, blue: 1.00)
        ]
        return colors[depth % colors.count]
    }
}
