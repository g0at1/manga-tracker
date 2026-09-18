import AppKit
import SwiftUI

/// Turns off the native AppKit selection highlight of the `NSTableView`
/// (and its `NSTableRowView`s) backing a SwiftUI `List`, so rows can draw
/// their own selection background via `.listRowBackground`.
///
/// Needed because macOS ignores the app's `AccentColor` whenever the user
/// picks a non‑multicolor accent in System Settings, which would otherwise
/// force that system color onto the selected row.
///
/// The view is meant to live inside a row. It re-applies the style every
/// time it is attached or laid out, synchronously, because SwiftUI resets
/// the table's highlight style when the selection changes.
private final class SelectionHighlightHidingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideHighlight()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hideHighlight()
    }

    override func layout() {
        super.layout()
        hideHighlight()
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func hideHighlight() {
        var current = superview
        while let view = current {
            if let row = view as? NSTableRowView {
                Self.hide(row)
            }
            if let table = view as? NSTableView {
                if table.selectionHighlightStyle != .none {
                    table.selectionHighlightStyle = .none
                }
                table.enumerateAvailableRowViews { row, _ in Self.hide(row) }
                return
            }
            current = view.superview
        }
    }

    private static func hide(_ row: NSTableRowView) {
        guard row.selectionHighlightStyle != .none else { return }
        row.selectionHighlightStyle = .none
        row.needsDisplay = true
    }
}

private struct ListSelectionHighlightHider: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        SelectionHighlightHidingView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.needsLayout = true
    }
}

extension View {
    /// Apply to a `List` row to hide the system selection highlight, so the
    /// selected row's look is fully controlled by `.listRowBackground`.
    func listRowSelectionHighlightHidden() -> some View {
        background(ListSelectionHighlightHider())
    }
}
