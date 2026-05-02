import Combine
import SwiftUI

@MainActor
final class ToastService: ObservableObject {
    static let shared = ToastService()

    @Published var currentToast: ToastMessage?

    private init() {}

    func show(
        _ text: String,
        type: ToastType = .info,
        duration: TimeInterval = 3
    ) {
        let toast = ToastMessage(text: text, type: type)
        currentToast = toast

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            if self.currentToast?.id == toast.id {
                self.currentToast = nil
            }
        }
    }
}
