import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let description: String?
    let type: ToastType
    let duration: TimeInterval
}

enum ToastType {
    case success
    case error
    case info

    var color: Color {
        switch self {
        case .success: .green
        case .error: .red
        case .info: .blue
        }
    }

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }
}
