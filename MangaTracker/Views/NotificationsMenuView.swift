import SwiftUI

struct NotificationsMenuView: View {
    @ObservedObject var toastService: ToastService

    var body: some View {
        Menu {
            if toastService.inbox.isEmpty {
                Text("Brak powiadomień")
            } else {
                Button("Oznacz wszystkie jako przeczytane") {
                    toastService.markAllInboxAsRead()
                }

                Button("Usuń wszystkie", role: .destructive) {
                    toastService.deleteAllInbox()
                }

                Divider()

                ForEach(toastService.inbox) { entry in
                    Button {
                        toastService.markInboxEntryAsRead(entry.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: entry.message.type.icon)
                                Text(entry.message.text)
                                if !entry.isRead {
                                    Text("•")
                                        .foregroundStyle(.blue)
                                }
                            }
                            if let description = entry.message.description, !description.isEmpty {
                                Text(description)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(
                "Powiadomienia",
                systemImage: toastService.unreadInboxCount > 0 ? "bell.badge.fill" : "bell"
            )
        }
    }
}
