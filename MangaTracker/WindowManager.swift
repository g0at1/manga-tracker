import AppKit

enum WindowManager {
    static func maximizeMainWindow() {
        DispatchQueue.main.async {
            guard
                let window = NSApplication.shared.windows.first,
                let screen = window.screen ?? NSScreen.main
            else { return }

            let frame = screen.visibleFrame
            window.setFrame(frame, display: true, animate: false)
        }
    }

    /// macOS restores a window's last frame, which can leave a data-heavy
    /// window tiny; grow it (centered on its screen) up to what fits.
    static func ensureComfortableSize(windowID: String, minWidth: CGFloat, minHeight: CGFloat) {
        DispatchQueue.main.async {
            guard
                let window = NSApplication.shared.windows.first(where: {
                    $0.identifier?.rawValue.hasPrefix(windowID) == true
                }),
                let screen = window.screen ?? NSScreen.main
            else { return }

            let visible = screen.visibleFrame
            let width = min(max(window.frame.width, minWidth), visible.width)
            let height = min(max(window.frame.height, minHeight), visible.height)
            guard width > window.frame.width || height > window.frame.height else { return }

            let origin = CGPoint(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2
            )
            window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true, animate: true)
        }
    }
}
