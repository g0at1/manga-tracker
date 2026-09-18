import SwiftUI

/// Toolbar breadcrumb shown while a series is open:
/// `‹ Biblioteka › <title>`. The library part is the back button.
struct LibraryBreadcrumbView: View {
    let manga: Manga
    let onBack: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Biblioteka")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize()
                .foregroundStyle(isHovered ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isHovered ? 0.10 : 0))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help("Wróć do biblioteki (⌘←)")

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .fixedSize()

            Text(displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 12)
        }
        .padding(.leading, 4)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
    }

    /// Long titles are shortened here rather than by the toolbar, which would
    /// otherwise squeeze the "Biblioteka" button instead.
    private var displayTitle: String {
        let title = manga.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return "Bez tytułu" }
        let limit = 40
        return title.count > limit ? String(title.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : title
    }
}
