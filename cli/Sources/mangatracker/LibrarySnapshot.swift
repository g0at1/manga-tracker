import Foundation
import SQLite3
import SwiftData

/// A private copy of the Mac app's library, opened with the app's own models.
///
/// The live store is only ever read: SQLite's backup API copies it (WAL
/// included, consistent even while the app is writing) into a temporary
/// file, and SwiftData opens that. Any migration SwiftData decides to run
/// happens on the copy, and the copy is deleted on `close()`.
final class LibrarySnapshot {
    /// Where the sandboxed Mac app keeps its SwiftData store.
    static var defaultStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.michalL.MangaTracker/Data/Library/Application Support/default.store")
    }

    let container: ModelContainer
    private let directory: URL

    init(storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw CLIError("No library at \(storeURL.path). Has the Mac app been run on this account?")
        }
        directory = FileManager.default.temporaryDirectory
            .appending(path: "mangatracker-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let copyURL = directory.appending(path: "default.store")
        do {
            try Self.backup(from: storeURL, to: copyURL)
            container = try ModelContainer(
                for: Manga.self, Volume.self, VolumePart.self,
                configurations: ModelConfiguration(url: copyURL)
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func mangas() throws -> [Manga] {
        try container.mainContext.fetch(FetchDescriptor<Manga>())
    }

    func close() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func backup(from source: URL, to destination: URL) throws {
        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?
        defer {
            sqlite3_close(sourceDB)
            sqlite3_close(destinationDB)
        }

        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CLIError("Couldn't open \(source.path): \(message(sourceDB))")
        }
        guard sqlite3_open(destination.path, &destinationDB) == SQLITE_OK else {
            throw CLIError("Couldn't create the snapshot: \(message(destinationDB))")
        }
        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw CLIError("Couldn't copy the library: \(message(destinationDB))")
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE else {
            throw CLIError("Couldn't copy the library: \(String(cString: sqlite3_errstr(stepResult)))")
        }
    }

    private static func message(_ db: OpaquePointer?) -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
