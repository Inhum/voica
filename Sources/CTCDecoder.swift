// CTC-декодер для локального движка GigaAM.
//
// Модель отдаёт по кадру распределение на 257 «токенов»: 256 сабвордов
// (словарь sentencepiece, выгружен в плоский Resources/gigaam-vocab.txt)
// + blank (id 256). Декод: argmax по кадрам → схлопнуть повторы → выкинуть
// blank → склеить кусочки («▁» = начало слова → пробел).
// Сама библиотека sentencepiece не нужна: для декода достаточно таблицы id→кусочек.

import Foundation

struct CTCDecoder {
    private let pieces: [String]
    private let blankID: Int
    private let unkID = 0   // <unk> — пропускаем

    /// Загружает словарь из бандла (Resources/gigaam-vocab.txt, по строке на токен).
    init?() {
        guard let url = Bundle.main.url(forResource: "gigaam-vocab", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // не отбрасываем пустые строки: id должен совпадать с номером строки
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }   // хвостовой перевод строки
        pieces = lines
        blankID = lines.count   // blank = следующий id за словарём (256)
    }

    init(pieces: [String]) {
        self.pieces = pieces
        blankID = pieces.count
    }

    /// argmax-ids кадров → текст.
    func decode(_ ids: [Int]) -> String {
        var out = ""
        var prev = -1
        for id in ids {
            if id != prev && id != blankID && id != unkID && id < pieces.count {
                out += pieces[id]
            }
            prev = id
        }
        return out.replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
