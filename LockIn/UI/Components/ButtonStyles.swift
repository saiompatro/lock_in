import SwiftUI

/// Filled, brand-colored button for the main action on a surface.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var expands = true

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint, expands: expands)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let expands: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: 36)
                .frame(maxWidth: expands ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isEnabled ? AnyShapeStyle(tint.opacity(hovering ? 0.88 : 1)) : AnyShapeStyle(Color.primary.opacity(0.08)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(isEnabled ? 0.18 : 0), lineWidth: 0.5)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

/// Quiet tinted button for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var expands = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint, expands: expands)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let expands: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint == .primary ? Color.primary : tint)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(minHeight: 30)
                .frame(maxWidth: expands ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(hovering ? 0.16 : 0.09))
                )
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

/// Borderless icon button with a circular hover state.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = .secondary
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint, size: size)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? (tint == .secondary ? Color.primary : tint) : tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Circle())
        }
    }
}

/// Full-width row button (menu bar footer, sidebar-like items).
struct RowButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.08 : 0)))
                )
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var lockInPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func lockInPrimary(tint: Color = Theme.accent, expands: Bool = true) -> PrimaryButtonStyle {
        PrimaryButtonStyle(tint: tint, expands: expands)
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var lockInSoft: SoftButtonStyle { SoftButtonStyle() }
    static func lockInSoft(tint: Color = .primary, expands: Bool = false) -> SoftButtonStyle {
        SoftButtonStyle(tint: tint, expands: expands)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var lockInIcon: IconButtonStyle { IconButtonStyle() }
    static func lockInIcon(tint: Color = .secondary, size: CGFloat = 28) -> IconButtonStyle {
        IconButtonStyle(tint: tint, size: size)
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var lockInRow: RowButtonStyle { RowButtonStyle() }
    static func lockInRow(tint: Color = .primary) -> RowButtonStyle { RowButtonStyle(tint: tint) }
}
