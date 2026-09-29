import Foundation
import CSQLite

public struct CatalogEntry: Equatable, Sendable {
    public let id: String
    public let isSubagent: Bool
}

public enum CatalogFailure: Error, LocalizedError {
    case missingDatabase, database(String)
    public var errorDescription: String? {
        switch self {
        case .missingDatabase: return "Nenalezena databáze Codexu. Spusť desktopovou aplikaci Codex."
        case .database(let message): return "Nelze přečíst seznam chatů: \(message)"
        }
    }
}

public struct ThreadCatalog {
    public let home: URL
    public init(home: URL) { self.home = home }

    public func entries() throws -> [CatalogEntry] {
        let files = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
        let database = files.compactMap { file -> (URL, Int)? in
            let name = file.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (file, version)
        }.max { $0.1 < $1.1 }?.0
        guard let database else { throw CatalogFailure.missingDatabase }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let reason = db.map { String(cString: sqlite3_errmsg($0)) } ?? "soubor nelze otevřít"
            sqlite3_close(db); throw CatalogFailure.database(reason)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var query: OpaquePointer?
        // No config or credential files are opened. The active DB remains read-only, including WAL mode.
        let sql = "SELECT id, source FROM threads WHERE archived = 0 AND (source IN ('cli','vscode','exec') OR source LIKE '%thread_spawn%') ORDER BY updated_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK else {
            throw CatalogFailure.database(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(query) }
        var result: [CatalogEntry] = []
        var code = sqlite3_step(query)
        while code == SQLITE_ROW {
            if let id = sqlite3_column_text(query, 0), let source = sqlite3_column_text(query, 1) {
                let source = String(cString: source)
                result.append(CatalogEntry(id: String(cString: id), isSubagent: source.contains("thread_spawn")))
            }
            code = sqlite3_step(query)
        }
        guard code == SQLITE_DONE else { throw CatalogFailure.database(String(cString: sqlite3_errmsg(db))) }
        return result
    }
}
