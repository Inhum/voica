// Детерминированная нормализация распознанного текста (§6).
//
// Правила, а не модель: ноль скачивания, ноль ОЗУ, работает офлайн и одинаково на обоих
// движках. Живёт в общем хвосте распознавания, ДО ИИ-исправления терминов (§6.1) —
// модель получает уже прибранный текст, и ей остаётся только то, что требует смысла.
//
// Зачем вообще: у LLM нет порога ни в одну сторону. На живых диктовках она один и тот же
// искажённый термин то чинила (`Dпсик`, `Deepsic`), то не замечала (`Deepsc`), а однажды
// подменила словарным термином слово, которого в словаре не было. У правила порог фиксирован.

import Foundation

enum Normalizer {

    /// Кириллица → латиница: сравнивать `Dпсик` с `DeepSeek` можно только в одном алфавите.
    private static let translit: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
        "з": "z", "и": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
        "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e",
        "ю": "yu", "я": "ya",
    ]

    /// Слово написано в двух алфавитах сразу. В нормальном русском тексте так не бывает —
    /// это след локального движка: у GigaAM латиница нарезана по одной букве (§2.5), поэтому
    /// иностранные термины выходят вперемешку: `Dпсик`, `Dpсиcк`, `раadio`.
    /// Признак надёжнее фонетической близости и не даёт ложных срабатываний на обычном тексте.
    static func hasMixedScript(_ word: String) -> Bool {
        var latin = false, cyrillic = false
        for ch in word.lowercased() where ch.isLetter {
            if translit[ch] != nil { cyrillic = true } else if ch.isASCII { latin = true }
            if latin && cyrillic { return true }
        }
        return false
    }

    /// Согласный костяк: транслитерируем, выкидываем гласные, сводим `c` к `k`, схлопываем
    /// повторы. Гласные выкидываем потому, что именно их модель теряет и путает, а согласные
    /// держатся. Проверено на живых искажениях `DeepSeek` — `Dпсик`, `Dпсиcк`, `Deepsc`,
    /// `Dpсиcк` дают тот же костяк `dpsk`, что и сам термин.
    static func skeleton(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            let piece: String
            if let t = translit[ch] { piece = t }
            else if ch.isLetter, ch.isASCII { piece = String(ch) }
            else { continue }                       // цифры, дефисы, пунктуация — мимо
            for c in piece where !"aeiouy".contains(c) {
                let folded: Character = (c == "c") ? "k" : c
                if out.last != folded { out.append(folded) }
            }
        }
        return out
    }

    /// Заменяет искорёженные словарные термины на канонические написания.
    /// Кандидаты — только слова со смешанным алфавитом; совпадение — по согласному костяку.
    /// Пунктуация и пробелы сохраняются как есть.
    static func fixTerms(_ text: String, vocabulary: String) -> String {
        let terms = vocabulary.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return text }

        var out = "", word = ""
        func flush() {
            guard !word.isEmpty else { return }
            out += replacement(for: word, terms: terms) ?? word
            word = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber { word.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }

    /// Слово в латинице, приведённое к одному виду: для сравнения искажения с термином.
    private static func latinized(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if let t = translit[ch] { out += t }
            else if ch.isLetter, ch.isASCII { out.append(ch) }
        }
        return out
    }

    /// Расстояние Левенштейна, приведённое к доле совпадения (1 — одинаковые).
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1,
                             prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// Канонический термин для искажённого слова, либо nil — трогать не надо.
    ///
    /// Кандидаты двух сортов, и требования к ним РАЗНЫЕ:
    /// • **смешанный алфавит** (`Dпсик`) — сам по себе доказательство порчи, хватает совпадения
    ///   костяка. Побуквенно такое слово от термина далеко, сравнивать его бессмысленно.
    /// • **чистая латиница** (`Deepsc`) — сама по себе ничего не доказывает: в русской диктовке
    ///   попадаются и нормальные английские слова. Поэтому вдобавок к костяку требуем побуквенную
    ///   близость. Без этого «Greek» превратился бы в «Groq» — костяк у них один (`grk`).
    private static func replacement(for word: String, terms: [String]) -> String? {
        let mixed = hasMixedScript(word)
        let onlyLatin = !mixed && word.allSatisfy { !$0.isLetter || $0.isASCII }
        guard mixed || onlyLatin else { return nil }

        let sk = skeleton(word)
        guard sk.count >= 2 else { return nil }     // однобуквенный костяк ничего не доказывает
        var hits = terms.filter { skeleton($0) == sk }
        if onlyLatin {
            let w = latinized(word)
            hits = hits.filter { similarity(w, latinized($0)) >= 0.6 }
        }
        guard !hits.isEmpty else { return nil }
        // Несколько терминов с одним костяком — берём ближайший по длине к сказанному.
        return hits.min { abs($0.count - word.count) < abs($1.count - word.count) }
    }
}
