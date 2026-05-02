import SwiftUI
import Combine

@MainActor
final class ToastService: ObservableObject {
    static let shared = ToastService()

    @Published private(set) var toasts: [ToastMessage] = []

    private let maxToasts = 4

    private init() {}

    func show(
        _ text: String,
        type: ToastType = .info,
        duration: TimeInterval = 3
    ) {
        let toast = ToastMessage(text: text, type: type, duration: duration)

        if toasts.count >= maxToasts {
            toasts.removeLast()
        }

        toasts.insert(toast, at: 0)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            dismiss(toast)
        }
    }

    func dismiss(_ toast: ToastMessage) {
        toasts.removeAll { $0.id == toast.id }
    }
}
