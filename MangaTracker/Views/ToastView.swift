import SwiftUI

struct ToastView: View {
    let message: ToastMessage

    @State private var progress: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: message.type.icon)
                    .foregroundStyle(message.type.color)
                    .padding(.top, 2)

                Text(message.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button {
                    dismissNow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            GeometryReader { proxy in
                Rectangle()
                    .fill(message.type.color)
                    .frame(width: proxy.size.width * progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
        }
        .frame(width: 340)
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
