import SwiftUI

/// Pill-shaped filter toggle with an optional count, used above grids and tables.
struct FilterChip: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isSelected ? Color.black.opacity(0.25) : Color.white.opacity(0.08)
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.85) : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.green
                        : Color.white.opacity(isHovered ? 0.1 : 0.05)
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
