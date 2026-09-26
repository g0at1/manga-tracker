import SwiftUI

/// Left column: library sections with counts, plus shortcuts to the
/// dashboard window and settings.
struct NavigationSidebarView: View {
    let categoryCounts: [LibraryCategory: Int]

    @Binding var category: LibraryCategory
    @ObservedObject var toastService: ToastService

    @State private var isShowingNotifications = false

    /// Header logo: back to the unfiltered library.
    let onGoHome: () -> Void
    let onOpenStatistics: () -> Void
    let onOpenUpcoming: () -> Void
    let onOpenShelf: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onGoHome) {
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("MangaTracker")
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tooltip("Strona główna")
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 22)

            VStack(spacing: 2) {
                ForEach(LibraryCategory.allCases) { section in
                    row(
                        section.label,
                        systemImage: section.systemImage,
                        count: categoryCounts[section, default: 0],
                        isSelected: category == section
                    ) {
                        category = section
                    }
                }
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            VStack(spacing: 2) {
                row("Statystyki", systemImage: "chart.bar", action: onOpenStatistics)
                row("Nadchodzące", systemImage: "calendar.badge.clock", action: onOpenUpcoming)
                row("Półka", systemImage: "books.vertical", action: onOpenShelf)
                row(
                    "Powiadomienia",
                    systemImage: toastService.unreadInboxCount > 0 ? "bell.badge" : "bell",
                    badge: toastService.unreadInboxCount
                ) {
                    isShowingNotifications.toggle()
                }
                .popover(isPresented: $isShowingNotifications, arrowEdge: .trailing) {
                    NotificationsPopoverView(toastService: toastService)
                }
                row("Ustawienia", systemImage: "gearshape", action: onOpenSettings)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppBackgroundView())
    }

    private func row(
        _ title: LocalizedStringKey,
        systemImage: String,
        count: Int? = nil,
        badge: Int = 0,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        SidebarRow(
            title: title,
            systemImage: systemImage,
            count: count,
            badge: badge,
            isSelected: isSelected,
            action: action
        )
    }
}

private struct SidebarRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let count: Int?
    /// Unread-style red badge; hidden when zero.
    let badge: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.green : .secondary)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer(minLength: 8)

                if let count {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? Color.green : Color.secondary.opacity(0.7))
                }

                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.green.opacity(0.16)
                            : Color.white.opacity(isHovered ? 0.05 : 0)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
