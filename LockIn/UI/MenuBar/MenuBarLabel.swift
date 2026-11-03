import SwiftUI

/// The menu bar icon (+ optional timer text). Reads `model.now` so it refreshes every second.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.status.menuBarSymbolName)
            if let text = timerText {
                Text(text)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var timerText: String? {
        guard model.isSessionActive, model.settings.showTimerInMenuBar else { return nil }
        let now = model.now
        let engine = model.engine
        switch model.status {
        case .idle:
            return nil
        case .studying:
            return DurationFormat.clock(engine.focusedTime(at: now))
        case .distracted:
            return DurationFormat.clock(engine.currentDistractionElapsed(at: now))
        case .paused:
            if let remaining = engine.breakRemaining(at: now) {
                return DurationFormat.clock(remaining)
            }
            return "Paused"
        }
    }

    private var accessibilityText: String {
        if let timerText { return "Lock In, \(model.status.displayName), \(timerText)" }
        return "Lock In, \(model.status.displayName)"
    }
}
