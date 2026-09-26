import SwiftUI

/// Contents of the notifications popover opened from the sidebar.
struct NotificationsPopoverView: View {
    @ObservedObject var toastService: ToastService

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .opacity(0.5)

            if toastService.inbox.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(toastService.inbox) { entry in
                            NotificationRow(entry: entry) {
                                toastService.markInboxEntryAsRead(entry.id)
                            } onDelete: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    toastService.deleteInboxEntry(entry.id)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 400)
        .background(AppBackgroundView())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Powiadomienia")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()

            if toastService.unreadInboxCount > 0 {
                Text("\(toastService.unreadInboxCount) nowe")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.16), in: Capsule())
            }

            Spacer(minLength: 8)

            if !toastService.inbox.isEmpty {
                HeaderAction(systemImage: "checkmark.circle", help: "Oznacz wszystkie jako przeczytane") {
                    toastService.markAllInboxAsRead()
                }
                .disabled(toastService.unreadInboxCount == 0)

                HeaderAction(systemImage: "trash", help: "Usuń wszystkie") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        toastService.deleteAllInbox()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("Brak powiadomień")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Tutaj pojawią się informacje o eksporcie, imporcie i danych z AniList.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

private struct HeaderAction: View {
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? .secondary : .quaternary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isHovered && isEnabled ? 0.1 : 0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .tooltip(help)
        .onHover { isHovered = $0 }
    }
}

private struct NotificationRow: View {
    let entry: ToastInboxEntry
    let onRead: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var message: ToastMessage {
        entry.message
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(message.type.color.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: message.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(message.type.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 13, weight: entry.isRead ? .regular : .semibold))
                    .foregroundStyle(entry.isRead ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let description = message.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(message.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .tooltip("Usuń")
                } else if !entry.isRead {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    entry.isRead
                        ? Color.white.opacity(isHovered ? 0.05 : 0)
                        : Color.white.opacity(isHovered ? 0.08 : 0.045)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onRead)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
