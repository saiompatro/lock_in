import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats over everything (including full-screen apps).
/// It can become key so its buttons (and Esc) work after a click, but it never activates Lock In
/// and is never made key automatically, so the user's typing is not hijacked when it appears.
final class DistractionOverlayPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Lets the very first click hit a button even though the panel is not key yet.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Creates, reuses and animates the overlay panel.
@MainActor
final class DistractionOverlayController {
    private var panel: DistractionOverlayPanel?
    private var model: DistractionOverlayModel?
    /// Invalidates in-flight fade-out completions when a new `show` arrives mid-fade.
    private var generation = 0

    var isVisible: Bool { panel != nil && model?.isDismissing == false }

    /// Show the overlay, or just update the visible one (repeat reminders do not stack).
    func show(context: AlertContext,
              breakMinutes: Double,
              isPreview: Bool,
              onReturn: @escaping () -> Void,
              onBreak: @escaping () -> Void,
              onEnd: @escaping () -> Void,
              onCancel: @escaping () -> Void) {
        generation += 1

        if let panel, let model {
            // Already on screen (or fading out): refresh in place.
            let wasDismissing = model.isDismissing
            model.update(context: context, breakMinutes: breakMinutes, isPreview: isPreview, pulse: !wasDismissing)
            install(actions: (onReturn, onBreak, onEnd, onCancel), model: model, panel: panel)
            if wasDismissing {
                panel.setFrame(Self.targetScreen()?.frame ?? panel.frame, display: true)
                animateAlpha(of: panel, to: 1, duration: 0.2)
            }
            return
        }

        let model = DistractionOverlayModel(context: context, breakMinutes: breakMinutes, isPreview: isPreview)
        let screen = Self.targetScreen()
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = DistractionOverlayPanel(contentRect: frame,
                                            styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered,
                                            defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let hosting = FirstMouseHostingView(rootView: DistractionOverlayView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        install(actions: (onReturn, onBreak, onEnd, onCancel), model: model, panel: panel)

        self.model = model
        self.panel = panel

        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        // Never `makeKey`: the user may be typing in another app right now.
        panel.orderFrontRegardless()
        animateAlpha(of: panel, to: 1, duration: 0.28)
    }

    /// Fade the card and backdrop out, then remove the panel.
    func hide() {
        guard let panel, let model else { return }
        guard !model.isDismissing else { return }
        generation += 1
        let token = generation
        model.isDismissing = true
        animateAlpha(of: panel, to: 0, duration: 0.22) { [weak self] in
            guard let self, self.generation == token else { return }
            panel.orderOut(nil)
            panel.contentView = nil
            self.panel = nil
            self.model = nil
        }
    }

    // MARK: Helpers

    private func install(actions: (() -> Void, () -> Void, () -> Void, () -> Void),
                         model: DistractionOverlayModel,
                         panel: DistractionOverlayPanel) {
        model.onReturn = actions.0
        model.onBreak = actions.1
        model.onEnd = actions.2
        model.onCancel = actions.3
        panel.onCancel = actions.3
    }

    private func animateAlpha(of panel: NSPanel, to value: CGFloat, duration: TimeInterval,
                              completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: value > 0 ? .easeOut : .easeIn)
            panel.animator().alphaValue = value
        } completionHandler: {
            if let completion {
                MainActor.assumeIsolated { completion() }
            }
        }
    }

    /// The screen that currently contains the mouse, falling back to the main screen.
    static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
