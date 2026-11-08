import Foundation
import SQLite3

/// A value bound to a `?` parameter of a statement.
enum SQLiteValue {
    case int(Int)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

/// Thin wrapper over one SQLite connection (C API). Not thread-safe: it is
/// owned and serialised by `LibraryStore`.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// SQLite copies bound strings itself.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens the database file. `create` adds `SQLITE_OPEN_CREATE`,
    /// `readOnly` opens without write access.
    init(path: String, create: Bool = true, readOnly: Bool = false) throws {
        var flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        if create && !readOnly { flags |= SQLITE_OPEN_CREATE }
        flags |= SQLITE_OPEN_NOMUTEX
        var db: OpaquePointer?
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(db)
            throw PersistenceError.sqlite(code: result, message: message)
        }
        sqlite3_extended_result_codes(db, 1)
        handle = db
    }

    deinit { close() }

    /// Closes the connection; later calls fail with `SQLITE_MISUSE`.
    func close() {
        if let handle {
            sqlite3_close_v2(handle)
        }
        handle = nil
    }

    /// The raw connection, for the backup API.
    var rawHandle: OpaquePointer? { handle }

    private func connection() throws -> OpaquePointer {
        guard let handle else {
            throw PersistenceError.sqlite(code: SQLITE_MISUSE, message: "database is closed")
        }
        return handle
    }

    private func error(_ code: Int32) -> PersistenceError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(code))
        return .sqlite(code: code, message: message)
    }

    /// Sets the busy timeout in milliseconds.
    func setBusyTimeout(_ milliseconds: Int32) throws {
        let code = sqlite3_busy_timeout(try connection(), milliseconds)
        if code != SQLITE_OK { throw error(code) }
    }

    /// Runs one or more statements without parameters.
    func executeScript(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(try connection(), sql, nil, nil, &message)
        if code != SQLITE_OK {
            let text = message.map { String(cString: $0) } ?? String(cString: sqlite3_errstr(code))
            sqlite3_free(message)
            throw PersistenceError.sqlite(code: code, message: text)
        }
    }

    /// Runs one statement that returns no rows.
    func execute(_ sql: String, _ parameters: [SQLiteValue] = []) throws {
        try withStatement(sql, parameters) { statement in
            let code = sqlite3_step(statement)
            if code != SQLITE_DONE && code != SQLITE_ROW { throw error(code) }
        }
    }

    /// The rows the last INSERT, UPDATE or DELETE changed.
    var changes: Int {
        guard let handle else { return 0 }
        return Int(sqlite3_changes(handle))
    }

    /// Runs one query and maps every row.
    func query<T>(_ sql: String, _ parameters: [SQLiteValue] = [], row map: (Row) throws -> T) throws -> [T] {
        try withStatement(sql, parameters) { statement in
            var result: [T] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                guard code == SQLITE_ROW else { throw error(code) }
                result.append(try map(Row(statement: statement)))
            }
            return result
        }
    }

    /// Runs `body` inside a transaction; it is rolled back when `body` throws.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try executeScript("BEGIN")
        do {
            let value = try body()
            try executeScript("COMMIT")
            return value
        } catch {
            try? executeScript("ROLLBACK")
            throw error
        }
    }

    private func withStatement<T>(_ sql: String, _ parameters: [SQLiteValue], _ body: (OpaquePointer) throws -> T) throws -> T {
        let db = try connection()
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw error(prepared)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch parameter {
            case let .int(value):
                code = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case let .double(value):
                code = sqlite3_bind_double(statement, index, value)
            case let .text(value):
                code = sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case let .blob(value):
                // SQLITE_TRANSIENT: the bytes outlive the statement only inside
                // this call, so SQLite has to copy them.
                code = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
                }
            case .null:
                code = sqlite3_bind_null(statement, index)
            }
            if code != SQLITE_OK { throw error(code) }
        }
        return try body(statement)
    }

    /// One result row; valid only inside the `query` closure.
    struct Row {
        fileprivate let statement: OpaquePointer

        func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }

        func double(_ column: Int32) -> Double {
            sqlite3_column_double(statement, column)
        }

        /// The bytes of the column; NULL or empty reads as empty data.
        func blob(_ column: Int32) -> Data {
            guard let pointer = sqlite3_column_blob(statement, column) else { return Data() }
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0 else { return Data() }
            return Data(bytes: pointer, count: count)
        }

        /// The text of the column; NULL reads as "" (like Go's NullString).
        func text(_ column: Int32) -> String {
            guard let pointer = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: pointer)
        }

        func isNull(_ column: Int32) -> Bool {
            sqlite3_column_type(statement, column) == SQLITE_NULL
        }
    }

    /// Copies the whole database `source` into this connection (SQLite
    /// online backup API), replacing its content.
    func restore(from source: SQLiteDatabase) throws {
        let destination = try connection()
        guard let sourceHandle = source.rawHandle else {
            throw PersistenceError.sqlite(code: SQLITE_MISUSE, message: "source database is closed")
        }
        guard let backup = sqlite3_backup_init(destination, "main", sourceHandle, "main") else {
            throw error(sqlite3_errcode(destination))
        }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        if step != SQLITE_DONE { throw PersistenceError.sqlite(code: step, message: String(cString: sqlite3_errstr(step))) }
        if finish != SQLITE_OK { throw error(finish) }
    }
}
