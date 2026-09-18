import SwiftUI

struct ToastView: View {
    let message: ToastMessage

    @State private var progress: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: message.type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(message.type.color)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let description = message.description,
                       !description.isEmpty
                    {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    dismissNow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            GeometryReader { proxy in
                Rectangle()
                    .fill(message.type.color)
                    .frame(width: proxy.size.width * progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
        }
        .frame(width: 420)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .onAppear {
            progress = 1

            withAnimation(.linear(duration: message.duration)) {
                progress = 0
            }
        }
    }

    private func dismissNow() {
        withAnimation {
            progress = 0
        }

        ToastService.shared.dismiss(message)
    }
}

/// Stack of active toasts in the window's top-right corner. Owns the
/// observation of `ToastService` so only this overlay re-renders when a
/// toast comes or goes.
struct ToastOverlayView: View {
    @ObservedObject var toastService: ToastService

    var body: some View {
        ZStack {
            if !toastService.toasts.isEmpty {
                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(toastService.toasts) { toast in
                        ToastView(message: toast)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 20)
                .padding(.trailing, 20)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
            }
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.85),
            value: toastService.toasts
        )
    }
}
