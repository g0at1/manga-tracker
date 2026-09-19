import SwiftData
import SwiftUI

/// App preferences: UI language and sync; the JSON backup as a share sheet.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var mangas: [Manga]

    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.polish.rawValue
    @State private var backupFile: URL?

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

                    DetailCard {
                        VStack(alignment: .leading, spacing: 12) {
                            DetailCardTitle(title: "Kopia zapasowa", systemImage: "externaldrive.fill")

                            Text("Ten sam format JSON, który eksportuje i importuje aplikacja na Macu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let backup = backupFile {
                                ShareLink(item: backup, preview: SharePreview(backup.lastPathComponent)) {
                                    Label("Udostępnij eksport JSON", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                        }
                    }

                    Text("MangaTracker \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .background(AppBackgroundView())
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            .onAppear(perform: writeBackupFile)
        }
    }

    /// Writes the export to a temporary file, so the share sheet can hand
    /// it to Files, Mail or AirDrop.
    private func writeBackupFile() {
        guard let data = try? encodeMangasToJSON(mangas) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manga-export-\(Date().yyyyMMdd()).json")
        backupFile = (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }
}
