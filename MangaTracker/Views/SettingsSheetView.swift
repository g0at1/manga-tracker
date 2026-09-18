import SwiftUI

/// App preferences: UI language and backup reminders.
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.polish.rawValue

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

    var body: some View {
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
                            Text("Eksport do folderu Pobrane")
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

            HStack {
                Text("MangaTracker \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Gotowe") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(AppBackgroundView())
    }

    private var lastBackupText: Text {
        guard lastBackupAt > 0 else { return Text("Ostatni backup: nigdy") }
        let date = DateFormatters.yyyyMMdd.string(from: Date(timeIntervalSince1970: lastBackupAt))
        return Text("Ostatni backup: \(date)")
    }
}
