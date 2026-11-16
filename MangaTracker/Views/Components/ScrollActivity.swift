import SwiftUI

extension EnvironmentValues {
    /// True while the enclosing scroll view is moving. The pointer stays put
    /// as rows slide under it, so hover reacts to every row passing by;
    /// views use this to skip hover work until the scroll settles.
    @Entry var isScrolling = false
}

extension View {
    /// Publishes this scroll view's movement as `isScrolling` to its content.
    func tracksScrollActivity() -> some View {
        modifier(ScrollActivityModifier())
    }
}

/// Keeps the state here, so starting and stopping a scroll only touches
/// the views that read `isScrolling`, not the whole page.
private struct ScrollActivityModifier: ViewModifier {
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        content
            .environment(\.isScrolling, isScrolling)
            .onScrollPhaseChange { _, phase in
                isScrolling = phase.isScrolling
            }
    }
}
