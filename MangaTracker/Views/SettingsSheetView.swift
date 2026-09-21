import AppKit
import SwiftUI

/// App preferences: UI language, sync, e-mail reminders and backups.
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.polish.rawValue
    @AppStorage(ExportFolder.pathKey) private var exportFolderPath = ""

    @Binding var backupReminderIntervalDays: Int
    let lastBackupAt: Double
    let onExport: () -> Void
    let onImport: () -> Void

    private let intervals = [1, 3, 7, 14, 30]

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// The cards can outgrow a laptop screen, so they scroll once they
    /// pass this height (a sheet can't grow past its window); the footer
    /// with "Gotowe" stays put either way.
    private static let maxCardsHeight: CGFloat = {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return min(900, screen - 130)
    }()

    @State private var cardsHeight = Self.maxCardsHeight

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                cards
                    .padding(24)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardsHeight = $0 }
            }
            .frame(height: min(cardsHeight, Self.maxCardsHeight))

            Divider().overlay(Color.white.opacity(0.06))

            HStack {
                Text("MangaTracker \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Gotowe") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 480)
        .background(AppBackgroundView())
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ustawienia")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Preferencje aplikacji")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            DetailCard {
                VStack(alignment: .leading, spacing: 12) {
                    DetailCardTitle(title: "Język", systemImage: "globe")

                    Picker("Język aplikacji", selection: $languageRaw) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            SyncSettingsCard()

            ReminderSettingsCard()

            DetailCard {
                VStack(alignment: .leading, spacing: 14) {
                    DetailCardTitle(title: "Kopia zapasowa", systemImage: "externaldrive.fill")

                    HStack {
                        Text("Przypominaj o backupie co")
                            .font(.subheadline)
                        Spacer()
                        Picker("Przypominaj o backupie co", selection: $backupReminderIntervalDays) {
                            ForEach(intervals, id: \.self) { days in
                                Text(days == 1 ? "1 dzień" : "\(days) dni").tag(days)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Folder eksportu")
                                .font(.subheadline)
                            exportFolderText
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if !exportFolderPath.isEmpty {
                            SubtleButton(title: "Domyślny", systemImage: "arrow.uturn.backward", action: ExportFolder.reset)
                                .help("Wróć do folderu Pobrane")
                        }
                        SubtleButton(title: "Zmień…", systemImage: "folder", action: chooseExportFolder)
                            .help("Wybierz inny folder")
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Eksport do pliku JSON")
                                .font(.subheadline)
                            lastBackupText
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SubtleButton(title: "Importuj…", systemImage: "square.and.arrow.down", action: onImport)
                        AccentButton(title: "Eksportuj teraz", systemImage: "square.and.arrow.up", action: onExport)
                    }
                }
            }
        }
    }

    private var lastBackupText: Text {
        guard lastBackupAt > 0 else { return Text("Ostatni backup: nigdy") }
        let date = DateFormatters.yyyyMMdd.string(from: Date(timeIntervalSince1970: lastBackupAt))
        return Text("Ostatni backup: \(date)")
    }

    private var exportFolderText: Text {
        guard !exportFolderPath.isEmpty else { return Text("Pobrane (domyślny)") }
        return Text(verbatim: (exportFolderPath as NSString).abbreviatingWithTildeInPath)
    }

    private func chooseExportFolder() {
        do {
            if let url = try ExportFolder.choose() {
                ToastService.shared.show(L("Folder eksportu: %@", url.path), type: .success)
            }
        } catch {
            ToastService.shared.show(L("Nie udało się zapamiętać folderu: %@", error.localizedDescription), type: .error)
        }
    }
}
