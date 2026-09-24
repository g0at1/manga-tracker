import SwiftUI

/// A volume's cover, falling back in steps so a shelf never shows a blank:
/// the volume's own MangaDex cover, else the series cover with the volume
/// number on it, else a drawn cover tinted per series.
struct VolumeCoverView: View {
    let volume: Volume
    var cornerRadius: CGFloat = 6

    private var title: String {
        volume.manga?.title ?? ""
    }

    private var volumeURL: URL? {
        url(volume.coverURL)
    }

    private var seriesURL: URL? {
        url(volume.manga?.coverURL)
    }

    var body: some View {
        CachedAsyncImage(url: volumeURL ?? seriesURL) { image in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                    if volumeURL == nil {
                        // The series cover stands in for every volume, so
                        // the number is what tells them apart.
                        numberBadge
                    }
                } else {
                    DrawnVolumeCover(title: title, number: volume.number)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var numberBadge: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Text("\(volume.number)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(5)
            }
        }
    }

    private func url(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string)
    }
}

/// Stand-in cover for a volume with no art at all. The tint comes from the
/// title, so one series' volumes match each other on the shelf.
struct DrawnVolumeCover: View {
    let title: String
    let number: Int

    var body: some View {
        let hue = Self.hue(for: title)
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.55, brightness: 0.55),
                    Color(hue: hue, saturation: 0.65, brightness: 0.3),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Spine edge, so it reads as a book rather than a tile.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.black.opacity(0.25))
                    .frame(width: 6)
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("\(number)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.vertical, 10)
            .padding(.leading, 12)
            .padding(.trailing, 6)
        }
    }

    /// Stable across launches, unlike `String.hashValue`.
    static func hue(for title: String) -> Double {
        let sum = title.unicodeScalars.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ $1.value }
        return Double(sum % 360) / 360
    }
}
