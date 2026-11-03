import SwiftUI

// Shared design tokens. UI agent may extend this file but must not remove or rename existing members
// (the alert pop-up uses them too).

enum Theme {
    static let accent = Color(red: 0.353, green: 0.416, blue: 0.965)      // indigo-blue
    static let studying = Color(red: 0.20, green: 0.78, blue: 0.55)       // mint green
    static let distracted = Color(red: 1.00, green: 0.45, blue: 0.30)     // warm coral
    static let paused = Color(red: 0.55, green: 0.57, blue: 0.65)         // slate
    static let idle = Color.secondary

    static let cornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 8
}

// MARK: - Extended tokens

extension Theme {
    /// 8-pt grid.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)

    /// Indigo to violet brand gradient.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.07)
    static let subtleFill = Color.primary.opacity(0.05)

    /// Spring used for status changes and expanding sections.
    static let smooth: Animation = .smooth(duration: 0.35)
    static let snappy: Animation = .snappy(duration: 0.25)
}

extension SessionStatus {
    var color: Color {
        switch self {
        case .idle: Theme.idle
        case .studying: Theme.studying
        case .distracted: Theme.distracted
        case .paused: Theme.paused
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "moon.zzz"
        case .studying: "brain.head.profile"
        case .distracted: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        }
    }

    /// Glyph used in the menu bar (lock motif).
    var menuBarSymbolName: String {
        switch self {
        case .idle: "lock.open"
        case .studying: "lock.fill"
        case .distracted: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        }
    }
}
