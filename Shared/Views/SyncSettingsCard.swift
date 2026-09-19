import SwiftUI
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// The sync section of Ustawienia on both platforms: create or join a
/// library by key, see the connection state, resend or disconnect.
struct SyncSettingsCard: View {
    @Environment(SyncEngine.self) private var engine

    @State private var keyInput = ""
    @State private var showDisconnectConfirm = false
    @State private var didCopy = false

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Synchronizacja", systemImage: "arrow.triangle.2.circlepath")

                switch engine.status {
                case .unavailable:
                    unavailable
                case .disconnected:
                    disconnected
                case .connecting, .online, .offline, .error:
                    connected
                }
            }
        }
        .confirmationDialog(
            "Rozłączyć to urządzenie?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Rozłącz", role: .destructive) { engine.disconnect() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Biblioteka zostanie na tym urządzeniu, ale zmiany przestaną być wymieniane z pozostałymi.")
        }
    }

    // MARK: - States

    private var unavailable: some View {
        Text("Ta kompilacja nie ma konfiguracji Firebase (GoogleService-Info.plist). Zobacz sekcję „Synchronizacja” w README.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var disconnected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Połącz komputer i telefon jednym kluczem biblioteki. Utwórz go na pierwszym urządzeniu, potem wklej na drugim.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            AccentButton(title: "Utwórz nową bibliotekę", systemImage: "plus") {
                engine.createLibrary()
            }

            Text("albo dołącz do istniejącej")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                TextField("Klucz z drugiego urządzenia", text: $keyInput)
                    .detailInput()
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.characters)
                #endif
                    .onSubmit(join)

                SubtleButton(title: "Wklej", systemImage: "doc.on.clipboard") {
                    if let pasted = Self.pasteboardString() {
                        keyInput = pasted
                    }
                }

                AccentButton(title: "Połącz", systemImage: "link", action: join)
                    .disabled(LibraryKey.normalize(keyInput) == nil)
            }

            if !keyInput.isEmpty, LibraryKey.normalize(keyInput) == nil {
                Text("Klucz ma 24 znaki, np. ABCD-EFGH-JKMN-PQRS-TUVW-XYZ2.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Klucz biblioteki")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(LibraryKey.formatted(engine.libraryKey ?? ""))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    SubtleButton(title: didCopy ? "Skopiowano" : "Kopiuj", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                        Self.copyToPasteboard(LibraryKey.formatted(engine.libraryKey ?? ""))
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            didCopy = false
                        }
                    }
                }
            }

            statusRow

            Divider().overlay(Color.white.opacity(0.06))

            HStack(spacing: 8) {
                SubtleButton(title: "Wyślij całą bibliotekę", systemImage: "icloud.and.arrow.up") {
                    engine.pushEverything()
                }
                Spacer()
                SubtleButton(title: "Rozłącz", systemImage: "xmark.circle", tint: .red) {
                    showDisconnectConfirm = true
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                if engine.pendingCount > 0 {
                    Text(L("Oczekujące zmiany: %lld", engine.pendingCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusColor: Color {
        switch engine.status {
        case .online: .green
        case .connecting: .yellow
        case .offline: .orange
        case .error: .red
        case .unavailable, .disconnected: .gray
        }
    }

    private var statusText: String {
        switch engine.status {
        case .connecting:
            L("Łączenie…")
        case let .online(lastSync):
            lastSync.map { L("Online · zsynchronizowano %@", Self.timeFormatter.string(from: $0)) } ?? L("Online")
        case .offline:
            L("Offline — zmiany zostaną wysłane po połączeniu")
        case let .error(message):
            L("Błąd: %@", message)
        case .unavailable, .disconnected:
            ""
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Actions

    private func join() {
        guard let key = LibraryKey.normalize(keyInput) else { return }
        engine.connect(libraryKey: key)
        keyInput = ""
    }

    private static func pasteboardString() -> String? {
        #if canImport(AppKit)
            NSPasteboard.general.string(forType: .string)
        #else
            UIPasteboard.general.string
        #endif
    }

    private static func copyToPasteboard(_ string: String) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }
}
