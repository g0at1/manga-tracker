import SwiftUI

/// Backup settings — the only preferences the app has so far.
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var backupReminderIntervalDays: Int
    let lastBackupAt: Double
    let onExport: () -> Void
    let onImport: () -> Void

    private let intervals = [1, 3, 7, 14, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ustawienia")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 12) {
                Text("Kopia zapasowa")
                    .font(.headline)

                Picker("Przypominaj o backupie co", selection: $backupReminderIntervalDays) {
                    ForEach(intervals, id: \.self) { days in
                        Text(days == 1 ? "1 dzień" : "\(days) dni").tag(days)
                    }
                }

                Text(lastBackupText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Eksportuj teraz", systemImage: "square.and.arrow.up", action: onExport)
                    Button("Importuj…", systemImage: "square.and.arrow.down", action: onImport)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )

            HStack {
                Spacer()
                Button("Gotowe") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var lastBackupText: String {
        guard lastBackupAt > 0 else { return "Ostatni backup: nigdy" }
        let date = Date(timeIntervalSince1970: lastBackupAt)
        return "Ostatni backup: \(DateFormatters.yyyyMMdd.string(from: date))"
    }
}
