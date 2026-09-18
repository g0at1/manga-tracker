import Combine
import SwiftUI

@MainActor
final class ToastService: ObservableObject {
    static let shared = ToastService()

    @Published private(set) var toasts: [ToastMessage] = []
    @Published private(set) var inbox: [ToastInboxEntry] = [] {
        didSet { persistInbox() }
    }

    private let maxToasts = 4
    /// Oldest entries are dropped past this so the store stays small.
    private let maxInboxEntries = 100
    private let inboxDefaultsKey = "notificationsInbox"

    private init() {
        inbox = loadInbox()
    }

    private func loadInbox() -> [ToastInboxEntry] {
        guard let data = UserDefaults.standard.data(forKey: inboxDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([ToastInboxEntry].self, from: data)) ?? []
    }

    private func persistInbox() {
        guard let data = try? JSONEncoder().encode(inbox) else { return }
        UserDefaults.standard.set(data, forKey: inboxDefaultsKey)
    }

    func show(
        _ text: String,
        description: String? = nil,
        type: ToastType = .info,
        duration: TimeInterval = 3
    ) {
        let toast = ToastMessage(
            text: text,
            description: description,
            type: type,
            duration: duration
        )

        if toasts.count >= maxToasts {
            toasts.removeLast()
        }

        toasts.insert(toast, at: 0)
        inbox.insert(ToastInboxEntry(message: toast), at: 0)
        if inbox.count > maxInboxEntries {
            inbox.removeLast(inbox.count - maxInboxEntries)
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            dismiss(toast)
        }
    }

    func dismiss(_ toast: ToastMessage) {
        toasts.removeAll { $0.id == toast.id }
    }

    var unreadInboxCount: Int {
        inbox.filter { !$0.isRead }.count
    }

    func markAllInboxAsRead() {
        inbox = inbox.map { entry in
            var updated = entry
            updated.isRead = true
            return updated
        }
    }

    func deleteAllInbox() {
        inbox.removeAll()
    }

    func markInboxEntryAsRead(_ id: UUID) {
        guard let index = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[index].isRead = true
    }

    func deleteInboxEntry(_ id: UUID) {
        inbox.removeAll { $0.id == id }
    }
}

struct ToastInboxEntry: Identifiable, Equatable, Codable {
    var id = UUID()
    let message: ToastMessage
    var isRead: Bool = false
}
