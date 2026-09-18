import AppKit
import Foundation

/// Where backups are written: a folder the user picked in Ustawienia, or
/// Downloads until they do.
///
/// The app is sandboxed, so a picked folder is kept as a security-scoped
/// bookmark — the only way to keep write access to it across launches.
enum ExportFolder {
    /// Display path of the chosen folder, empty when using Downloads.
    /// Views observe this through `@AppStorage`; the bookmark itself is
    /// only touched when exporting.
    static let pathKey = "exportFolderPath"
    private static let bookmarkKey = "exportFolderBookmark"

    enum AccessError: LocalizedError {
        case downloadsMissing
        case chosenFolderUnavailable

        var errorDescription: String? {
            switch self {
            case .downloadsMissing:
                L("Nie można znaleźć folderu Pobrane")
            case .chosenFolderUnavailable:
                L("Folder eksportu jest niedostępny. Wybierz go ponownie w Ustawieniach.")
            }
        }
    }

    static var isCustom: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Asks for a folder and remembers it. Returns `nil` when the user cancels.
    static func choose() throws -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("Wybierz folder, do którego będą zapisywane eksporty.")
        panel.prompt = L("Wybierz")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: pathKey)
        return url
    }

    /// Back to Downloads.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: pathKey)
    }

    /// Runs `body` with permission to write into the export folder.
    static func withWriteAccess<T>(_ body: (URL) throws -> T) throws -> T {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                throw AccessError.downloadsMissing
            }
            return try body(downloads)
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource()
        else {
            throw AccessError.chosenFolderUnavailable
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if isStale,
           let fresh = try? url.bookmarkData(
               options: .withSecurityScope,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           )
        {
            // The folder moved or was renamed; the system resolved it, so
            // save a bookmark that points at its new location.
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            UserDefaults.standard.set(url.path, forKey: pathKey)
        }

        return try body(url)
    }
}
