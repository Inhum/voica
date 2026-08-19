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
    /// Термин записан латиницей — значит в русском тексте не склоняется, и подставить его
    /// словарной формой безопасно. Русские термины правила НЕ трогают: сказано «отправь
    /// аферту», скелет совпадает с «оферта» точно, но подстановка дала бы «отправь оферта».
    /// Склонение требует понимания смысла — это работа §6.1.
    private static func isLatinTerm(_ t: String) -> Bool {
        !t.lowercased().contains { translit[$0] != nil }
    }

    /// Разделитель внутри составного термина: слова идут подряд, а не через конец предложения.
    private static func joinable(_ sep: String) -> Bool {
        !sep.isEmpty && sep.allSatisfy { $0 == " " || $0 == "-" || $0 == "\u{2011}" }
    }

    static func fixTerms(_ text: String, vocabulary: String) -> String {
        let terms = vocabulary.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return text }

        // Речь режется на слова, а термин может быть составным («Tail scale» вместо
        // Tailscale), поэтому сопоставляем окнами — от самых длинных к коротким.
        var pieces: [(sep: String, word: String)] = []
        var sep = "", word = ""
        for ch in text {
            if ch.isLetter || ch.isNumber { word.append(ch) }
            else {
                if !word.isEmpty { pieces.append((sep, word)); sep = ""; word = "" }
                sep.append(ch)
            }
        }
        if !word.isEmpty { pieces.append((sep, word)); sep = "" }
        let trailing = sep

        // Ширина окна не выводится из числа слов в термине: движок перекашивает в обе
        // стороны — «Claude Code» приезжает одним словом «клодкод», а «Tailscale» двумя
        // («Tail scale»). Двух слов хватает на все живые случаи, шире — лишний риск.
        let maxWindow = 2
        var out = ""
        var i = 0
        while i < pieces.count {
            var matched = false
            var n = min(maxWindow, pieces.count - i)
            while n >= 1 {
                // Окно шире одного слова склеиваем, только если слова идут подряд.
                let gapsOK = n == 1 || (1..<n).allSatisfy { joinable(pieces[i + $0].sep) }
                // В склейке каждое слово должно давать хоть одну согласную. Иначе окно
                // проглатывает пустышку: «дипсик и» даёт тот же костяк dpsk, что и «дипсик»,
                // потому что «и» — чистая гласная, и союз исчезал из текста.
                let allSubstantial = n == 1 || (0..<n).allSatisfy { !skeleton(pieces[i + $0].word).isEmpty }
                if gapsOK && allSubstantial {
                    let joined = (0..<n).map { pieces[i + $0].word }.joined()
                    // Окно шире одного слова — уже допущение. Второе допущение поверх него
                    // (нестрогий костяк) съедает соседей: «в Cowork» склеивалось в вCowork,
                    // расходилось с Cowork на одну букву и глотало предлог. Для склеек —
                    // только точное совпадение.
                    if let term = replacement(for: joined, terms: terms, exactOnly: n > 1) {
                        out += pieces[i].sep + term
                        i += n; matched = true; break
                    }
                }
                n -= 1
            }
            if !matched { out += pieces[i].sep + pieces[i].word; i += 1 }
        }
        return out + trailing
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

    /// Канонический термин для искажённого слова (или склейки слов), либо nil — не трогать.
    ///
    /// Кандидаты трёх сортов, и требования к ним РАЗНЫЕ — мягкость позволительна ровно
    /// настолько, насколько доказана порча:
    /// • **смешанный алфавит** (`Dпсик`) — доказательство само по себе, в русском тексте так
    ///   не пишут. Хватает костяка, допускается расхождение на одну согласную.
    /// • **чистая латиница** (`Deepsc`) — ничего не доказывает, в русской диктовке полно
    ///   английских слов. Костяк должен совпасть точно, плюс побуквенная близость ≥ 0.6,
    ///   иначе «Greek» стало бы «Groq».
    /// • **чистая кириллица** (`клодкод`) — не доказывает ничего вовсе. Только точный костяк
    ///   **от четырёх букв**. Мера вымерена на живых ловушках: «Вика» даёт костяк Voica
    ///   один в один, «Папа» — API, «усы» — ЕИС, а при малейшем послаблении «депеша»
    ///   становится DeepSeek (0.75), «Колодка» — Claude Code (0.80).
    private static func replacement(for word: String, terms: [String],
                                    exactOnly: Bool = false) -> String? {
        let mixed = hasMixedScript(word)
        let hasCyrillic = word.lowercased().contains { translit[$0] != nil }
        let onlyLatin = !hasCyrillic
        let onlyCyrillic = hasCyrillic && !mixed

        // Минимальная длина костяка — по силе доказательства порчи. Смешанный алфавит
        // доказывает сам себя, латинице и кириллице верить нечему. Мера не из головы:
        // на полном прогоне истории «vice versa» стало «Voica versa» — костяк vk совпал
        // с Voica, а побуквенная близость вышла ровно 0.60, впритык. Подкручивать порог до
        // 0.62 значило бы подгонять под один случай; короткий костяк не значит ничего в принципе.
        let minSkeleton = mixed ? 2 : (onlyCyrillic ? 4 : 3)
        let sk = skeleton(word)
        guard sk.count >= minSkeleton else { return nil }

        var hits = terms.filter { t in
            guard isLatinTerm(t) else { return false }
            let ts = skeleton(t)
            if ts == sk { return true }
            guard !exactOnly, mixed, sk.count >= 3, ts.count >= 3 else { return false }
            return similarity(sk, ts) >= 0.75
        }
        if onlyLatin {
            let w = latinized(word)
            hits = hits.filter { similarity(w, latinized($0)) >= 0.6 }
        }
        guard !hits.isEmpty else { return nil }
        // Несколько терминов с одним костяком — берём ближайший по длине к сказанному.
        return hits.min { abs($0.count - word.count) < abs($1.count - word.count) }
    }
}
