import SwiftUI

// MARK: - Card surface

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l
    var radius: CGFloat = Theme.cornerRadius + 2

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    /// Rounded, softly outlined surface used for dashboard and list cards.
    func card(padding: CGFloat = Theme.Spacing.l, radius: CGFloat = Theme.cornerRadius + 2) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }
}

// MARK: - Page header

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let status: SessionStatus
    var label: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(status.color.opacity(0.4), lineWidth: 3)
                        .opacity(status == .studying || status == .distracted ? 1 : 0)
                )
            Text(label ?? status.displayName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(status == .idle ? Color.secondary : status.color)
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(status.color.opacity(status == .idle ? 0.1 : 0.14)))
        .animation(Theme.smooth, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(label ?? status.displayName)")
    }
}

// MARK: - Kind badge

struct KindBadge: View {
    let kind: StudySpaceKind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbolName).font(.system(size: 9, weight: .bold))
            Text(kind.displayName.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var tint: Color {
        switch kind {
        case .app: Theme.accent
        case .window: Theme.violet
        case .website: Theme.studying
        }
    }
}

// MARK: - Progress ring

struct ProgressRing<Center: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
            center()
        }
        .animation(.smooth(duration: 0.6), value: progress)
        .animation(Theme.smooth, value: tint)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let title: String
    let value: String
    var symbol: String?
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(Theme.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Larger metric card used on the dashboard.
struct MetricCard: View {
    let title: String
    let value: String
    var caption: String?
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.snappy, value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Focus bar

/// Horizontal stacked bar: focused / distracted / paused shares of a session.
struct FocusBar: View {
    var focused: TimeInterval
    var distracted: TimeInterval
    var paused: TimeInterval = 0
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = max(focused + distracted + paused, 1)
            HStack(spacing: 2) {
                segment(focused / total, Theme.studying, width: geo.size.width)
                segment(distracted / total, Theme.distracted, width: geo.size.width)
                segment(paused / total, Theme.paused.opacity(0.6), width: geo.size.width)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focused \(UIFormat.duration(focused)), distracted \(UIFormat.duration(distracted))")
    }

    @ViewBuilder
    private func segment(_ fraction: Double, _ color: Color, width: CGFloat) -> some View {
        if fraction > 0.001 {
            Capsule().fill(color).frame(width: max(4, width * fraction))
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.brandGradient)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.lockInPrimary(expands: false))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - Selectable row

/// A tappable row with a leading selection indicator, used by the add-space pickers.
struct SelectableRow<Content: View>: View {
    var isSelected: Bool
    var isDisabled = false
    var multiple = true
    var action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                content()
                Spacer(minLength: Theme.Spacing.xs)
                indicator
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(Theme.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var indicator: some View {
        if isDisabled {
            Text("Added")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: isSelected ? (multiple ? "checkmark.circle.fill" : "largecircle.fill.circle") : (multiple ? "circle" : "circle"))
                .font(.system(size: 17))
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.5))
                .symbolEffect(.bounce, value: isSelected)
        }
    }
}

// MARK: - Small helpers

/// Section caption used above groups of rows.
struct CaptionHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Soft inline info/warning callout.
struct Callout: View {
    var symbol = "info.circle.fill"
    var tint: Color = Theme.accent
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 13))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.08)))
    }
}
