import AppKit
import SwiftUI

extension View {
    /// App-styled replacement for `.help`: shows faster than the system
    /// tooltip and matches the dark UI. `nil` shows nothing.
    func tooltip(_ text: Text?) -> some View {
        modifier(TooltipModifier(text: text))
    }

    func tooltip(_ key: LocalizedStringKey?) -> some View {
        tooltip(key.map { Text($0) })
    }

    /// For text that is already localized (`L(...)`) or not meant to be.
    /// Empty strings show nothing.
    @_disfavoredOverload
    func tooltip<S: StringProtocol>(_ text: S?) -> some View {
        tooltip(text.flatMap { $0.isEmpty ? nil : Text($0) })
    }
}

private struct TooltipModifier: ViewModifier {
    let text: Text?

    @Environment(\.locale) private var locale
    @State private var id = UUID()
    @State private var anchor = TooltipAnchorBox()

    func body(content: Content) -> some View {
        // Always attached, so a tooltip that comes and goes (`cond ? "…" : nil`)
        // doesn't change the identity of the view it's on.
        content
            .background(TooltipAnchor(box: anchor))
            .onHover { isHovering in
                if isHovering, let text, let view = anchor.view {
                    TooltipController.shared.schedule(
                        TooltipBubble(text: text).environment(\.locale, locale),
                        owner: id,
                        anchor: view
                    )
                } else {
                    TooltipController.shared.cancel(owner: id)
                }
            }
            .onDisappear { TooltipController.shared.cancel(owner: id) }
    }
}

private struct TooltipBubble: View {
    let text: Text

    var body: some View {
        text
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(white: 0.14).opacity(0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            // Room for the shadow inside the transparent panel.
            .padding(TooltipController.margin)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Anchor

/// Gives the modifier the AppKit view under it, to place the panel in
/// screen coordinates.
@MainActor
private final class TooltipAnchorBox {
    weak var view: NSView?
}

private struct TooltipAnchor: NSViewRepresentable {
    let box: TooltipAnchorBox

    func makeNSView(context _: Context) -> NSView {
        let view = PassthroughView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        box.view = nsView
    }

    private final class PassthroughView: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}

// MARK: - Controller

/// One borderless panel shared by all tooltips. Living in its own window, a
/// tooltip is never clipped by the sidebar, toolbar, popovers or scroll views.
@MainActor
private final class TooltipController {
    static let shared = TooltipController()

    static let margin: CGFloat = 10
    private static let maxTextWidth: CGFloat = 260
    private static let initialDelay: Duration = .milliseconds(400)
    /// Moving between controls while a tooltip is (or just was) up shows the
    /// next one right away, like the system does.
    private static let warmWindow: TimeInterval = 0.5

    private let panel: NSPanel
    private let hosting = NSHostingController(rootView: AnyView(EmptyView()))
    private var owner: UUID?
    private var pending: Task<Void, Never>?
    private var lastHiddenAt = Date.distantPast

    private init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        hosting.sizingOptions = []
        panel.contentViewController = hosting

        // Clicking, typing or scrolling dismisses the tooltip; it comes back
        // only after the pointer leaves and re-enters.
        NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { event in
            MainActor.assumeIsolated { TooltipController.shared.hide() }
            return event
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { TooltipController.shared.hide() }
        }
    }

    func schedule(_ content: some View, owner: UUID, anchor: NSView) {
        pending?.cancel()
        self.owner = owner

        let isWarm = panel.isVisible || Date().timeIntervalSince(lastHiddenAt) < Self.warmWindow
        let content = AnyView(content)
        pending = Task { [weak anchor] in
            if !isWarm {
                try? await Task.sleep(for: Self.initialDelay)
            }
            guard !Task.isCancelled, let anchor, self.owner == owner else { return }
            self.show(content, at: anchor)
        }
    }

    func cancel(owner: UUID) {
        guard self.owner == owner else { return }
        hide()
    }

    func hide() {
        pending?.cancel()
        pending = nil
        owner = nil
        if panel.isVisible {
            panel.orderOut(nil)
            lastHiddenAt = Date()
        }
    }

    private func show(_ content: AnyView, at anchor: NSView) {
        guard NSApp.isActive, let window = anchor.window, window.isVisible,
              let screen = window.screen ?? NSScreen.main
        else { return }

        hosting.rootView = content
        let chrome = Self.margin * 2 + 18
        let size = hosting.sizeThatFits(in: CGSize(width: Self.maxTextWidth + chrome, height: 10000))
        let bubble = CGSize(width: size.width - Self.margin * 2, height: size.height - Self.margin * 2)

        let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = screen.visibleFrame
        let gap: CGFloat = 6
        var origin: CGPoint
        let aboveY: CGFloat
        if anchorRect.height > 64 {
            // Big views (cards, shelf spines): follow the pointer instead of
            // hanging off the far edge.
            let mouse = NSEvent.mouseLocation
            origin = CGPoint(x: mouse.x - bubble.width / 2, y: mouse.y - 22 - bubble.height)
            aboveY = mouse.y + 12
        } else {
            origin = CGPoint(x: anchorRect.midX - bubble.width / 2, y: anchorRect.minY - gap - bubble.height)
            aboveY = anchorRect.maxY + gap
        }
        if origin.y < visible.minY + 4 {
            origin.y = aboveY
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - 4 - bubble.width)

        panel.setFrame(
            CGRect(
                x: origin.x - Self.margin,
                y: origin.y - Self.margin,
                width: size.width,
                height: size.height
            ),
            display: true
        )

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }
}
