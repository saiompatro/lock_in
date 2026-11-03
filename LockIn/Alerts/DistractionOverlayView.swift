import SwiftUI
import AppKit

// MARK: - Model

/// State shared between the overlay controller and the SwiftUI card.
@MainActor
@Observable
final class DistractionOverlayModel {
    private(set) var context: AlertContext
    private(set) var breakMinutes: Double
    private(set) var isPreview: Bool
    /// Bumped on every repeat reminder: drives the shake + icon bounce.
    private(set) var attentionPulse = 0
    /// Moment `context.distractedFor` was measured, so the text can count up live.
    private(set) var measuredAt = Date()
    /// Set while the overlay fades out so the card can animate away together with the panel.
    var isDismissing = false

    var onReturn: () -> Void = {}
    var onBreak: () -> Void = {}
    var onEnd: () -> Void = {}
    var onCancel: () -> Void = {}

    init(context: AlertContext, breakMinutes: Double, isPreview: Bool) {
        self.context = context
        self.breakMinutes = breakMinutes
        self.isPreview = isPreview
    }

    func update(context: AlertContext, breakMinutes: Double, isPreview: Bool, pulse: Bool) {
        self.context = context
        self.breakMinutes = breakMinutes
        self.isPreview = isPreview
        measuredAt = Date()
        isDismissing = false
        if pulse { attentionPulse += 1 }
    }

    // MARK: Text

    var primaryTitle: String {
        if let name = context.lastStudySpace?.name, !name.isEmpty { return "Back to \(name)" }
        return "Back to studying"
    }

    var breakTitle: String {
        let minutes = max(1, breakMinutes)
        let text = minutes == minutes.rounded() ? String(Int(minutes)) : String(format: "%.1f", minutes)
        return "Take a \(text)-minute break"
    }

    func subtitle(at date: Date) -> String {
        let away = context.distractedFor + max(0, date.timeIntervalSince(measuredAt))
        var text = "You've been away from your study spaces for \(Self.spoken(away))"
        if let app = context.distractingAppName, !app.isEmpty {
            text += ", on \(app)"
        }
        return text
    }

    /// "42 seconds", "5 minutes", "1 hour 5 minutes".
    static func spoken(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        if s < 60 { return s == 1 ? "1 second" : "\(s) seconds" }
        let minutes = s / 60
        if minutes < 60 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let h = minutes / 60, m = minutes % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        return m == 0 ? hours : "\(hours) \(m) \(m == 1 ? "minute" : "minutes")"
    }
}

// MARK: - Backdrop blur

/// Behind-window blur for the dimmed backdrop.
private struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Shake

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = animatableData - animatableData.rounded(.down)
        let envelope = sin(progress * .pi)                 // fades in and out, 0 at rest
        let x = 12 * envelope * sin(progress * .pi * 8)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

// MARK: - Buttons

private struct OverlayPrimaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.78)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(hovering ? 0.35 : 0.18), lineWidth: 1)
                    )
                    .shadow(color: Theme.accent.opacity(hovering ? 0.55 : 0.35), radius: hovering ? 14 : 8, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.015 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

private struct OverlaySecondaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.20 : (hovering ? 0.15 : 0.09)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

private struct OverlayTertiaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(hovering ? Theme.distracted : .white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Overlay

struct DistractionOverlayView: View {
    let model: DistractionOverlayModel
    @State private var appeared = false
    @State private var glow = false

    private var cardVisible: Bool { appeared && !model.isDismissing }

    var body: some View {
        ZStack {
            BackdropBlur()
            Color.black.opacity(0.35)

            card
                .scaleEffect(cardVisible ? 1 : (model.isDismissing ? 0.96 : 0.9))
                .opacity(cardVisible ? 1 : 0)
                .modifier(ShakeEffect(animatableData: CGFloat(model.attentionPulse)))
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
        }
        .onExitCommand { model.onCancel() }
        .animation(.easeInOut(duration: 0.22), value: model.isDismissing)
        .animation(.linear(duration: 0.55), value: model.attentionPulse)
    }

    private var card: some View {
        VStack(spacing: 0) {
            icon
                .padding(.bottom, 22)

            Text("Time to lock back in")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(model.subtitle(at: timeline.date))
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Button(action: model.onReturn) {
                    Label(model.primaryTitle, systemImage: "arrow.uturn.backward.circle.fill")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(OverlayPrimaryButtonStyle())

                Button(action: model.onBreak) {
                    Label(model.breakTitle, systemImage: "cup.and.saucer.fill")
                        .lineLimit(1)
                }
                .buttonStyle(OverlaySecondaryButtonStyle())

                Button("End session", action: model.onEnd)
                    .buttonStyle(OverlayTertiaryButtonStyle())
                    .padding(.top, 2)
            }
            .padding(.top, 28)

            Button(action: model.onCancel) {
                Text(model.isPreview ? "Preview — nothing will change · Close" : "Dismiss")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Hide this reminder. The distraction timer keeps running.")
            .padding(.top, 10)
        }
        .padding(.horizontal, 34)
        .padding(.top, 38)
        .padding(.bottom, 22)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.distracted.opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 50, y: 24)
        )
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Theme.distracted.opacity(glow ? 0.30 : 0.14))
                .frame(width: 118, height: 118)
                .blur(radius: 14)
            Circle()
                .fill(LinearGradient(colors: [Theme.distracted, Color(red: 1, green: 0.62, blue: 0.28)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 84, height: 84)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Theme.distracted.opacity(0.55), radius: 16, y: 6)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating)
                .symbolEffect(.bounce, value: model.attentionPulse)
        }
        .frame(height: 118)
        .accessibilityHidden(true)
    }
}
