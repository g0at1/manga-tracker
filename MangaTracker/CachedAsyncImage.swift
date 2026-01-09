import Combine
import SwiftUI

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false

    func load(from url: URL?) async {
        guard let url else {
            self.image = nil
            return
        }

        if let data = ImageCache.shared.data(for: url),
            let img = NSImage(data: data)
        {
            self.image = img
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else {
                return
            }
            ImageCache.shared.store(data, for: url)
            self.image = NSImage(data: data)
        } catch {
        }
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    @StateObject private var loader = ImageLoader()

    var body: some View {
        ZStack {
            if let img = loader.image {
                Image(nsImage: img)
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
        .task(id: url?.absoluteString) {
            await loader.load(from: url)
        }
    }
}
