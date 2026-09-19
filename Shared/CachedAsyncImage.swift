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
struct BannerImageView: View {
    let url: URL?
    let size: CGSize

    var body: some View {
        CachedAsyncImage(url: url, maxPixelSize: ImageCache.bannerMaxPixelSize) { image in
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .opacity(0.6)
            }
        }
    }
}
