import RightClickKitCore
import SwiftUI

enum StorageFormatter {
    static func bytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(max(bytes, 0))
        var unit = 0

        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }

        if unit == 0 {
            return "\(Int(size)) \(units[unit])"
        }
        return String(format: "%.1f %@", size, units[unit])
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

enum StoragePalette {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor).opacity(0.62)
    static let centerBackground = Color(nsColor: .controlBackgroundColor).opacity(0.70)
    static let metricBackground = Color.primary.opacity(0.045)
    static let panelStroke = Color.primary.opacity(0.08)
    static let segmentStroke = Color(nsColor: .windowBackgroundColor).opacity(0.58)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let divider = Color.primary.opacity(0.09)
    static let track = Color.primary.opacity(0.11)
    static let blue = Color.accentColor
    static let warning = Color(red: 1.0, green: 0.45, blue: 0.35)

    private static let palette: [(red: Double, green: Double, blue: Double)] = [
        (0.30, 0.95, 0.48),
        (0.35, 0.87, 0.96),
        (0.46, 0.49, 1.00),
        (0.92, 0.28, 0.96),
        (1.00, 0.30, 0.56),
        (1.00, 0.36, 0.33),
        (0.96, 0.70, 0.28),
        (0.58, 0.60, 0.65)
    ]

    static func segmentColor(index: Int, depth: Int, synthetic: Bool) -> Color {
        if synthetic {
            return Color(red: 0.48, green: 0.50, blue: 0.54)
        }

        let base = palette[index % palette.count]
        let amount = min(0.10 * Double(max(depth - 1, 0)), 0.36)
        return Color(
            red: base.red * (1 - amount) + amount,
            green: base.green * (1 - amount) + amount,
            blue: base.blue * (1 - amount) + amount
        )
    }
}

extension StorageAnalysisNode {
    var stableID: String {
        "\(path)|\(name)|\(synthetic)"
    }
}
