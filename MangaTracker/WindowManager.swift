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
}
