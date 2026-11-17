import SwiftUI

/// Thin reading-progress bar for cards. Drawn with shapes instead of
/// `ProgressView`, which hosts a platform control per card and is slower to
/// build while a grid scrolls.
struct ReadingProgressBar: View {
    /// 0 to 1.
    let fraction: Double
    var height: CGFloat = 3

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.1))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.green)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: height)
    }
}
