// Хранилище истории транскрибаций (SQLite) и аудиофайлов.
//
// Данные живут вне .app, чтобы переживать обновление:
//   ~/Library/Application Support/com.ushakov.voica/history.sqlite
//   ~/Library/Application Support/com.ushakov.voica/audio/*.m4a

import Foundation
import SQLite3

struct TranscriptRecord {
    let id: Int64
    let createdAt: Date
    let text: String
    let language: String?
    let durationSec: Double?
    let audioFilename: String?
    let model: String?
}

final class Store {
    static let shared = Store()

    private var db: OpaquePointer?
    private let dir: URL
    private let audioDir: URL
    // SQLITE_TRANSIENT: sqlite копирует переданные байты (строки живут недолго).
    private static let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func appSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.ushakov.voica", isDirectory: true)
    }

    private init() {
        dir = Store.appSupportDir()
        audioDir = dir.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let path = dir.appendingPathComponent("history.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("Voica: не удалось открыть БД: \(String(cString: sqlite3_errmsg(db)))")
        }
        exec("""
            CREATE TABLE IF NOT EXISTS transcriptions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at INTEGER NOT NULL,
              text TEXT NOT NULL,
              language TEXT,
              duration_sec REAL,
              audio_filename TEXT,
              model TEXT
            );
            """)
        cleanupExpiredAudio()
    }

    // MARK: - Запись

    /// Сохраняет транскрибацию. Если включено хранение аудио — переносит файл
    /// из temp в хранилище. Возвращает id новой записи.
    @discardableResult
    func insert(text: String, language: String?, duration: Double?,
                model: String?, audioTempURL: URL?) -> Int64? {
        var audioFilename: String?
        if Prefs.storeAudio, let src = audioTempURL {
            let name = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).m4a"
            let dest = audioDir.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: src, to: dest)
                audioFilename = name
            } catch {
                NSLog("Voica: не удалось сохранить аудио: \(error.localizedDescription)")
            }
        }

        let sql = """
            INSERT INTO transcriptions (created_at, text, language, duration_sec, audio_filename, model)
            VALUES (?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_text(stmt, 2, text, -1, Store.TRANSIENT)
        bindOptText(stmt, 3, language)
        if let d = duration { sqlite3_bind_double(stmt, 4, d) } else { sqlite3_bind_null(stmt, 4) }
        bindOptText(stmt, 5, audioFilename)
        bindOptText(stmt, 6, model)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return sqlite3_last_insert_rowid(db)
    }

    // MARK: - Чтение

    func all() -> [TranscriptRecord] {
        let sql = """
            SELECT id, created_at, text, language, duration_sec, audio_filename, model
            FROM transcriptions ORDER BY created_at DESC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [TranscriptRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(TranscriptRecord(
                id: sqlite3_column_int64(stmt, 0),
                createdAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1))),
                text: colText(stmt, 2) ?? "",
                language: colText(stmt, 3),
                durationSec: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 4),
                audioFilename: colText(stmt, 5),
                model: colText(stmt, 6)
            ))
        }
        return rows
    }

    func audioURL(for record: TranscriptRecord) -> URL? {
        guard let name = record.audioFilename else { return nil }
        let url = audioDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Сводка для подтверждения удаления (этап 4).
    func counts() -> (records: Int, audioFiles: Int) {
        let recs = all()
        return (recs.count, recs.filter { audioURL(for: $0) != nil }.count)
    }

    // MARK: - Удаление

    func delete(id: Int64) {
        if let rec = all().first(where: { $0.id == id }), let url = audioURL(for: rec) {
            try? FileManager.default.removeItem(at: url)
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM transcriptions WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    /// Полная очистка (для кнопки Delete all data).
    func deleteAll() {
        exec("DELETE FROM transcriptions;")
        if let files = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// Удаляет аудио старше retentionDays. Запись и текст остаются, ссылка обнуляется.
    func cleanupExpiredAudio() {
        let days = Prefs.retentionDays
        guard days > 0 else { return }
        let cutoff = Int64(Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970)

        var sel: OpaquePointer?
        if sqlite3_prepare_v2(db,
            "SELECT audio_filename FROM transcriptions WHERE audio_filename IS NOT NULL AND created_at < ?;",
            -1, &sel, nil) == SQLITE_OK {
            sqlite3_bind_int64(sel, 1, cutoff)
            while sqlite3_step(sel) == SQLITE_ROW {
                if let name = colText(sel, 0) {
                    try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(name))
                }
            }
        }
        sqlite3_finalize(sel)

        var upd: OpaquePointer?
        if sqlite3_prepare_v2(db,
            "UPDATE transcriptions SET audio_filename = NULL WHERE created_at < ?;",
            -1, &upd, nil) == SQLITE_OK {
            sqlite3_bind_int64(upd, 1, cutoff)
            sqlite3_step(upd)
        }
        sqlite3_finalize(upd)
    }

    // MARK: - Низкоуровневые помощники

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bindOptText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, idx, v, -1, Store.TRANSIENT) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func colText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }
}
