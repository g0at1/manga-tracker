import SwiftUI

/// The e-mail reminders section of Ustawienia on both platforms: switch
/// reminders on, pick the address and how many days ahead, see what the
/// server did last and send a test e-mail. Everything is stored on the
/// library document, so the settings need a connected library.
struct ReminderSettingsCard: View {
    @Environment(SyncEngine.self) private var engine

    /// The address as typed; saved after a pause or when the field is left.
    @State private var emailDraft = ""
    @State private var emailSaveTask: Task<Void, Never>?
    @FocusState private var emailFocused: Bool

    /// After this long without an answer the server is probably not deployed.
    private static let testTimeout: TimeInterval = 30

    private var reminders: LibraryReminders {
        engine.reminders
    }

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                DetailCardTitle(title: "Przypomnienia e-mail", systemImage: "envelope.badge")

                if !engine.status.isConnected {
                    Text("Przypomnienia wysyła serwer synchronizacji, więc dochodzą także wtedy, gdy aplikacja jest zamknięta. Najpierw połącz bibliotekę w sekcji „Synchronizacja”.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let settings = reminders.settings {
                    form(settings)
                } else if let error = reminders.error {
                    // Most likely the project still has the rules from before
                    // reminders existed, which don't allow reading the document.
                    statusLine(Text(L("Nie udało się wczytać ustawień: %@", error)), color: .red)
                    Text("Serwer odrzucił odczyt. Wdróż aktualne reguły z firebase/firestore.rules (sekcja „Przypomnienia e-mail” w README).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Wczytywanie ustawień…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: reminders.settings?.email, initial: true) { _, saved in
            // Another device's edit, or our own echoing back; never while typing.
            if !emailFocused {
                emailDraft = saved ?? ""
            }
        }
        .onChange(of: emailFocused) { _, focused in
            if !focused {
                commitEmail()
            }
        }
        .onChange(of: emailDraft) { _, draft in
            scheduleEmailSave(draft)
        }
    }

    // MARK: - Form

    @ViewBuilder
    private func form(_ settings: ReminderSettings) -> some View {
        Text("Lista tomów z linkami do zakupu, wysyłana rano na kilka dni przed premierą.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Toggle(isOn: Binding(
            get: { settings.enabled },
            set: { enabled in update { $0.enabled = enabled } }
        )) {
            Text("Wysyłaj przypomnienia")
                .font(.subheadline)
        }
        .toggleStyle(.switch)
        #if os(macOS)
            .controlSize(.small)
        #endif

        VStack(alignment: .leading, spacing: 6) {
            Text("Adres e-mail")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("ty@example.com", text: $emailDraft)
                .detailInput()
                .focused($emailFocused)
                .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
            #endif
                .onSubmit(commitEmail)
            if let hint = emailHint(settings) {
                Text(hint.text)
                    .font(.caption)
                    .foregroundStyle(hint.color)
            }
        }

        HStack {
            Text("Ile dni przed premierą")
                .font(.subheadline)
            Spacer()
            Picker("Ile dni przed premierą", selection: Binding(
                get: { settings.daysBefore },
                set: { days in update { $0.daysBefore = days } }
            )) {
                ForEach(ReminderSettings.daysBeforeOptions, id: \.self) { days in
                    Text(days == 1 ? "1 dzień" : "\(days) dni").tag(days)
                }
            }
            .labelsHidden()
            #if os(macOS)
                .frame(width: 110)
            #endif
        }

        Divider().overlay(Color.white.opacity(0.06))

        status(settings)
    }

    private func emailHint(_ settings: ReminderSettings) -> (text: LocalizedStringKey, color: Color)? {
        let trimmed = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !ReminderSettings.isValidEmail(trimmed) {
            return ("Podaj poprawny adres e-mail.", .red)
        }
        if settings.enabled, trimmed.isEmpty {
            return ("Podaj adres, na który mają przychodzić przypomnienia.", .orange)
        }
        return nil
    }

    // MARK: - Status

    @ViewBuilder
    private func status(_ settings: ReminderSettings) -> some View {
        if let error = reminders.error {
            statusLine(Text(L("Nie udało się zapisać: %@", error)), color: .red)
        }

        if let log = reminders.log {
            if let error = log.lastError {
                statusLine(Text(L("Ostatnia wysyłka nie powiodła się: %@", error)), color: .red)
            }
            if let sentAt = log.lastSentAt {
                statusLine(Text("Ostatni e-mail: ") + Text(sentAt, format: .relative(presentation: .named)), color: .secondary)
            }
            if let runAt = log.lastRunAt {
                statusLine(Text("Ostatnie sprawdzenie premier: ") + Text(runAt, format: .relative(presentation: .named)), color: .secondary)
            } else if settings.enabled {
                statusLine(Text("Serwer sprawdza premiery raz dziennie rano; jeszcze nie sprawdzał."), color: .secondary)
            }
        } else if settings.enabled {
            statusLine(Text("Serwer sprawdza premiery raz dziennie rano; jeszcze nie sprawdzał."), color: .secondary)
        }

        VStack(alignment: .leading, spacing: 10) {
            testStatus(settings)
            SubtleButton(title: "Wyślij testowy e-mail", systemImage: "paperplane") {
                commitEmail()
                reminders.requestTest()
            }
            .disabled(!ReminderSettings.isValidEmail(emailDraft) || reminders.isTestPending)
        }
    }

    @ViewBuilder
    private func testStatus(_ settings: ReminderSettings) -> some View {
        if reminders.isTestPending, let requestedAt = settings.testRequestedAt {
            TimelineView(.periodic(from: requestedAt, by: 5)) { context in
                if context.date.timeIntervalSince(requestedAt) > Self.testTimeout {
                    statusLine(Text("Serwer nie odpowiada. Czy funkcje są wdrożone? Zobacz „Przypomnienia e-mail” w README."), color: .orange)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Wysyłanie testowego e-maila…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if let result = reminders.latestTestResult {
            if let error = result.error {
                statusLine(Text(L("Test nie powiódł się: %@", error)), color: .red)
            } else if let sentAt = result.sentAt {
                statusLine(Text("Testowy e-mail wysłany ") + Text(sentAt, format: .relative(presentation: .named)), color: .green)
            }
        } else {
            statusLine(Text("Sprawdź, czy wszystko działa, zanim nadejdzie pierwsza premiera."), color: .secondary)
        }
    }

    private func statusLine(_ text: Text, color: Color) -> some View {
        text
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Saving

    private func update(_ change: (inout ReminderSettings) -> Void) {
        guard var settings = reminders.settings else { return }
        change(&settings)
        reminders.save(settings)
    }

    /// Saves the draft once it's a plausible address (or cleared), a
    /// moment after the last keystroke.
    private func scheduleEmailSave(_ draft: String) {
        emailSaveTask?.cancel()
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard emailFocused, trimmed.isEmpty || ReminderSettings.isValidEmail(trimmed) else { return }
        emailSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            commitEmail()
        }
    }

    private func commitEmail() {
        emailSaveTask?.cancel()
        emailSaveTask = nil
        let trimmed = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let settings = reminders.settings, trimmed != settings.email else { return }
        // A half-typed address stays in the field with its hint; only a
        // usable one (or none) is worth sending to the server.
        guard trimmed.isEmpty || ReminderSettings.isValidEmail(trimmed) else { return }
        update { $0.email = trimmed }
    }
}
