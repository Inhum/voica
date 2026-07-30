// Экспорт истории транскрибаций в файл. Чистая сериализация (тестируется в самотестах);
// диалог сохранения и запись — в HistoryWindow. Только текст+метаданные (аудио не входит).

import Foundation

enum HistoryExporter {
    enum Format: String, CaseIterable {
        case markdown, csv, json
        /// Расширение файла: markdown → md, остальные совпадают с rawValue.
        var ext: String { self == .markdown ? "md" : rawValue }
        var displayName: String {
            switch self {
            case .markdown: return "Markdown (.md)"
            case .csv:      return "CSV (.csv)"
            case .json:     return "JSON (.json)"
            }
        }
    }

    /// Дата в стабильном машинно-читаемом виде (не зависит от локали системы).
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func serialize(_ records: [TranscriptRecord], as format: Format) -> String {
        switch format {
        case .markdown: return markdown(records)
        case .csv:      return csv(records)
        case .json:     return json(records)
        }
    }

    // MARK: - Форматы

    private static func markdown(_ records: [TranscriptRecord]) -> String {
        var out = "# Voica — history (\(records.count))\n"
        for r in records {
            out += "\n## \(dateFmt.string(from: r.createdAt))\n"
            let meta = [r.language,
                        r.durationSec.map { String(format: "%.1fs", $0) },
                        r.model].compactMap { $0 }.joined(separator: " · ")
            if !meta.isEmpty { out += "_\(meta)_\n" }
            out += "\n\(r.text)\n"
        }
        return out
    }

    private static func csv(_ records: [TranscriptRecord]) -> String {
        func esc(_ s: String) -> String {
            guard s.contains("\"") || s.contains(",") || s.contains("\n") else { return s }
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        // BOM — чтобы Excel корректно открывал кириллицу в UTF-8.
        var out = "\u{FEFF}created_at,text,language,duration_sec,model\n"
        for r in records {
            out += [dateFmt.string(from: r.createdAt),
                    r.text,
                    r.language ?? "",
                    r.durationSec.map { String(format: "%.2f", $0) } ?? "",
                    r.model ?? ""].map(esc).joined(separator: ",") + "\n"
        }
        return out
    }

    private static func json(_ records: [TranscriptRecord]) -> String {
        let iso = ISO8601DateFormatter()
        let arr: [[String: Any]] = records.map { r in
            var o: [String: Any] = ["id": r.id,
                                    "created_at": iso.string(from: r.createdAt),
                                    "text": r.text]
            o["language"] = r.language            // nil → ключ опускается
            o["duration_sec"] = r.durationSec
            o["model"] = r.model
            o["audio_filename"] = r.audioFilename
            return o
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
}
