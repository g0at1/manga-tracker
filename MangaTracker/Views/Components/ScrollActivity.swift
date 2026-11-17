import Observation
import SwiftUI

/// Whether the enclosing scroll view is moving. The pointer stays put as
/// rows slide under it, so hover reacts to every row passing by; views use
/// this to skip hover work until the scroll settles.
///
/// An observable object rather than a plain `Bool` in the environment: a
/// view only depends on `isScrolling` once it actually reads it, so reading
/// it behind `isHovered &&` means starting or stopping a scroll re-renders
/// just the one hovered row — not every row, chip and tooltip on screen.
@Observable
final class ScrollActivity {
    var isScrolling = false
}

extension EnvironmentValues {
    /// Set by `tracksScrollActivity()`; `nil` outside a tracked scroll view.
    @Entry var scrollActivity: ScrollActivity? = nil
}

extension View {
    /// Publishes this scroll view's movement as `scrollActivity` to its content.
    func tracksScrollActivity() -> some View {
        modifier(ScrollActivityModifier())
    }
}

private struct ScrollActivityModifier: ViewModifier {
    @State private var activity = ScrollActivity()

    func body(content: Content) -> some View {
        content
            .environment(\.scrollActivity, activity)
            .onScrollPhaseChange { _, phase in
                if activity.isScrolling != phase.isScrolling {
                    activity.isScrolling = phase.isScrolling
                }
            }
    }
}
