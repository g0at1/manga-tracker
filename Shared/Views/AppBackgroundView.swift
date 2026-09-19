import SwiftUI

/// Shared dark surface used behind every column so the sidebar,
/// library and detail views read as one surface.
///
/// A flat charcoal base with two soft radial glows: the app's green accent
/// in the top-left and a cool teal in the bottom-right.
struct AppBackgroundView: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.07)

            RadialGradient(
                colors: [
                    Color.green.opacity(0.14),
                    Color.green.opacity(0.04),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 900
            )

            RadialGradient(
                colors: [
                    Color.teal.opacity(0.10),
                    Color.teal.opacity(0.03),
                    .clear,
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 1100
            )

            // Slight vertical falloff so the bottom of tall windows stays grounded.
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
