import SwiftUI

/// Flat card used for every panel on the detail page.
struct DetailCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

/// Section title inside a `DetailCard`.
struct DetailCardTitle: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
            Text(title)
                .font(.headline)
        }
    }
}

/// Small translucent action button that sits on top of the banner.
struct GlassButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isEnabled ? 0.92 : 0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black.opacity(isHovered && isEnabled ? 0.55 : 0.4))
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct MetadataPill: View {
    let icon: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Green primary action button.
struct AccentButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(isEnabled ? (isHovered ? 1 : 0.9) : 0.35))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// Quiet secondary action button.
struct SubtleButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var tint: Color = .primary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// Text field chrome matching the detail cards.
    func detailInput(width: CGFloat? = nil) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

extension Binding where Value == String? {
    func orEmpty() -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}

func formatAniListStatus(_ status: String) -> String {
    switch status {
    case "FINISHED": L("Zakończona")
    case "RELEASING": L("Wydawana")
    case "NOT_YET_RELEASED": L("Jeszcze niewydana")
    case "CANCELLED": L("Anulowana")
    case "HIATUS": L("Wstrzymana")
    default: status
    }
}

// MARK: - Star rating

struct StarRatingView: View {
    @Binding var rating: Double
    @Binding var hoverRating: Double?

    var maxRating = 5
    var starSize: CGFloat = 24
    var spacing: CGFloat = 8

    private var displayedRating: Double {
        hoverRating ?? rating
    }

    private var totalWidth: CGFloat {
        CGFloat(maxRating) * starSize + CGFloat(maxRating - 1) * spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1 ... maxRating, id: \.self) { index in
                Image(systemName: imageName(for: index, rating: displayedRating))
                    .resizable()
                    .scaledToFit()
                    .frame(width: starSize, height: starSize)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(width: totalWidth, height: starSize, alignment: .leading)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                hoverRating = ratingValue(at: location.x)
            case .ended:
                hoverRating = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    hoverRating = ratingValue(at: value.location.x)
                }
                .onEnded { value in
                    rating = ratingValue(at: value.location.x)
                    hoverRating = nil
                }
        )
    }

    private func ratingValue(at x: CGFloat) -> Double {
        let clampedX = min(max(0, x), totalWidth)

        for index in 1 ... maxRating {
            let starStart = CGFloat(index - 1) * (starSize + spacing)
            let starEnd = starStart + starSize
            let hitStart = index == 1 ? 0 : starStart - spacing / 2
            let hitEnd = index == maxRating ? totalWidth : starEnd + spacing / 2

            guard clampedX >= hitStart, clampedX <= hitEnd else { continue }

            let localX = min(max(0, clampedX - starStart), starSize)
            return localX < starSize / 2 ? Double(index) - 0.5 : Double(index)
        }

        return 0
    }

    private func imageName(for index: Int, rating: Double) -> String {
        let value = Double(index)
        if rating >= value {
            return "star.fill"
        } else if rating == value - 0.5 {
            return "star.leadinghalf.filled"
        }
        return "star"
    }
}
