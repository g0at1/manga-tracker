import SwiftUI

/// Like `AsyncImage`, but served through `ImageCache`: decoded once, kept in
/// memory and on disk, and shared between every view showing the same URL.
/// `content` receives `nil` until the image is available.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let maxPixelSize: Int
    private let content: (CGImage?) -> Content

    @State private var image: CGImage?

    init(
        url: URL?,
        maxPixelSize: Int = ImageCache.coverMaxPixelSize,
        @ViewBuilder content: @escaping (CGImage?) -> Content
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content
        // Already decoded → draw it on the first frame instead of flashing a placeholder.
        _image = State(initialValue: url.flatMap {
            ImageCache.shared.cachedImage(for: $0, maxPixelSize: maxPixelSize)
        })
    }

    var body: some View {
        // `content` may be empty until the image arrives (the banner is), and
        // SwiftUI never runs `.task` on an empty view — so the task hangs off
        // a container that always exists.
        ZStack {
            content(image)
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImageCache.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                if cached !== image {
                    image = cached
                }
                return
            }
            let loaded = await ImageCache.shared.image(for: url, maxPixelSize: maxPixelSize)
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}

/// Rounded cover with a book placeholder until the image arrives.
struct CoverImageView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        CachedAsyncImage(url: url) { image in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.quaternary)
                    Image(systemName: "book")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Full-bleed banner that fades in at 60% opacity, sized by its container.
///
/// AniList banners are at most 1900px wide, so filling a wide window on a
/// Retina display stretches them about 2× and they turn soft and blocky.
/// Past `maxMagnification` the banner is drawn at that size instead,
/// centered, with its sides fading into a heavily blurred copy that fills
/// the rest of the width.
struct BannerImageView: View {
    let url: URL?
    let size: CGSize

    @Environment(\.displayScale) private var displayScale

    /// How far a banner pixel may be stretched before it starts to look soft.
    private static let maxMagnification: CGFloat = 1.5
    /// Width of the fade between the sharp banner and the blurred sides.
    private static let featherWidth: CGFloat = 140

    var body: some View {
        CachedAsyncImage(url: url, maxPixelSize: ImageCache.bannerMaxPixelSize) { image in
            if let image {
                ZStack {
                    let sharpWidth = sharpWidth(for: image)
                    if sharpWidth < size.width {
                        filled(image)
                            .blur(radius: 30, opaque: true)
                        sharp(image, width: sharpWidth)
                    } else {
                        filled(image)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(0.6)
            }
        }
    }

    private func filled(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func sharp(_ image: CGImage, width: CGFloat) -> some View {
        let feather = min(Self.featherWidth / width, 0.25)
        return Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: width, height: size.height)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: feather),
                        .init(color: .black, location: 1 - feather),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    /// Width, in points, of the banner drawn without stretching it past
    /// `maxMagnification`. It always covers the full height, so a very wide,
    /// short banner may still be stretched more than that.
    private func sharpWidth(for image: CGImage) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return size.width }
        let pointsPerPixel = max(
            Self.maxMagnification / max(displayScale, 1),
            size.height / CGFloat(image.height)
        )
        return CGFloat(image.width) * pointsPerPixel
    }
}
