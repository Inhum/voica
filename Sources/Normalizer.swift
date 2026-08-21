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

    // MARK: - Непарные кавычки

    /// Приводит кавычки в порядок: прямые заменяет ёлочками по положению, непарные убирает.
    ///
    /// Движок пишет кавычки как придётся — в его словаре есть и `«`, и `»`, и `"`, и он
    /// предсказывает каждую отдельно, без памяти о том, что уже открыл (§2.5). Живой пример:
    /// `в ответ:"Давай … неделе". Я сказал: «Да", это … вариант".` — три вида вперемешку.
    ///
    /// Стоит последней, в единственной точке выдачи, ПОСЛЕ обоих механизмов (§6.2 и §6.1):
    /// наследить может и движок, и модель, а виноватого не определить.
    static func balanceQuotes(_ text: String) -> String {
        let chars = Array(smartQuotes(text))
        var openIdx: [Int] = [], matched: [Int] = [], unmatched: [Int] = []
        var strays = Set<Int>()
        for (i, ch) in chars.enumerated() {
            if ch == "«" { openIdx.append(i) }
            else if ch == "»" {
                if openIdx.isEmpty { unmatched.append(i) }    // закрыли то, что не открывали
                else { openIdx.removeLast(); matched.append(i) }
            }
        }
        // На каждую лишнюю закрывающую надо что-то выбросить, и выбор неочевиден. Если какая-то
        // из УЖЕ СПАРЕННЫХ закрывающих выглядит преждевременной — за ней запятая и продолжение
        // со строчной, — выбрасываем её: значит цитата на самом деле длиннее, а лишняя закрывает
        // её по-настоящему. Живой случай: «Да", это стопроцентный вариант" — человек закавычил
        // всю фразу, движок закрыл после первого слова; правильный ответ «Да, это … вариант».
        // Если преждевременных нет, лишняя и есть ошибка — выбрасываем её саму. Иначе фраза
        // «Он сказал «да». Потом ушёл»» потеряла бы верную закрывающую после «да».
        for extra in unmatched {
            if let premature = matched.first(where: { isPremature(chars, at: $0) && !strays.contains($0) }) {
                strays.insert(premature)
            } else {
                strays.insert(extra)
            }
        }
        strays.formUnion(openIdx)                             // открыли и не закрыли
        guard !strays.isEmpty else { return String(chars) }
        return String(chars.enumerated().filter { !strays.contains($0.offset) }.map(\.element))
    }

    /// Закрывающая кавычка выглядит преждевременной: за ней запятая и продолжение со строчной,
    /// то есть фраза не кончилась и цитата, скорее всего, тоже.
    private static func isPremature(_ chars: [Character], at i: Int) -> Bool {
        var j = i + 1
        guard j < chars.count, chars[j] == "," else { return false }
        j += 1
        while j < chars.count, chars[j] == " " { j += 1 }
        guard j < chars.count else { return false }
        return chars[j].isLowercase
    }

    /// Прямая кавычка `"` не различает открывающую и закрывающую, поэтому определяем по
    /// соседям — как это делают текстовые редакторы: после пробела или двоеточия и перед
    /// буквой это открывающая, после буквы или знака — закрывающая.
    static func smartQuotes(_ text: String) -> String {
        // Ёлочки — русская типографика. В английском тексте прямые кавычки правильны, и
        // трогать их нельзя: диктовка бывает и на английском (§2 — авто-детект языка).
        guard text.lowercased().contains(where: { translit[$0] != nil }) else { return text }
        let chars = Array(text)
        var out = ""
        for (i, ch) in chars.enumerated() {
            guard ch == "\"" else { out.append(ch); continue }
            let before = i > 0 ? chars[i - 1] : " "
            let after = i + 1 < chars.count ? chars[i + 1] : " "
            let opening = (before == " " || before == ":" || before == "(" || before == "\n")
                && (after.isLetter || after.isNumber)
            // Движок часто забывает пробел после двоеточия перед цитатой: `в ответ:"Давай`.
            if opening, before == ":" { out.append(" ") }
            out.append(opening ? "«" : "»")
        }
        return out
    }

    // MARK: - Филлеры («э-э-э», «ммм», «хмм»)

    /// Схлопывает дефисы и подряд идущие одинаковые буквы: «Э-э-э» → «э», «Ну-у-у» → «ну».
    /// Тянущийся звук распознавание пишет по-разному от раза к разу, поэтому сравнивать
    /// надо именно свёрнутую форму, а не перечислять написания.
    static func collapsed(_ word: String) -> String {
        var out = ""
        for ch in word.lowercased() where ch != "-" && ch != "\u{2011}" {
            if out.last != ch { out.append(ch) }
        }
        return out
    }

    /// Свёрнутые формы, которые целиком являются мусором и удаляются даже без растяжки.
    ///
    /// ⚠️ Список обязан состоять из форм длиной **до двух букв** — ровно их пропускает гейт
    /// `col.count <= 2` ниже. Всё длиннее не сработает никогда и будет тихо лежать мёртвым:
    /// так тут и лежали `мхм`, `угу`, `ага` (нашлось при сверке с Windows).
    ///
    /// Их не вернули, подняв гейт, а убрали намеренно: «угу», «ага», «мхм» — это СОГЛАСИЕ,
    /// в них есть смысл, в отличие от мычания. Диктовка из одного «Ага.» после удаления
    /// стала бы пустой. Тот же довод, по которому растянутое «ну-у-у» распрямляется,
    /// а не выбрасывается.
    ///
    /// «эм» НЕ филлер по другой причине: так движок пишет «GigaAM» — «Джига Эм».
    private static let fillerWords: Set<String> = ["хм", "э"]
    /// Растянутые НАСТОЯЩИЕ слова, которые надо распрямить, а не удалить. Список явный:
    /// распрямлять всё подряд нельзя — «PPC» стало бы «Pc», «All» → «Al», «ноо» → «но».
    private static let stretchable: Set<String> = ["ну", "но", "да", "нет", "вот", "так"]
    /// Одиночные звуки — только если их ТЯНУЛИ. Само по себе «а» это союз, «у» и «о» —
    /// предлоги, «и» — союз; трогать их нельзя ни при каких условиях.
    ///
    /// ⚠️ «и» тут НЕТ намеренно. Движок пишет аббревиатуру «ИИ» и строчными — «ии», — а она
    /// сворачивается в «и» и удалялась бы как растянутый звук. Живой случай: «Проверка ии.»
    /// превращалось в «Проверка». Растянутое «и-и-и» встречается редко, аббревиатура — часто.
    private static let fillerSounds: Set<String> = ["э", "а", "ы", "у", "м", "о"]

    /// Убирает слова-паразиты, оставшиеся от растянутых звуков.
    ///
    /// Правило смотрит не на список написаний, а на форму слова: кандидат — токен, который
    /// после схлопывания повторов ужимается до одной-двух букв («эээ» → «э», «хмм» → «хм»).
    /// Обычные слова так не ужимаются: «мама» остаётся «мама», «коммуникации» — «комуникации»,
    /// то есть длина остаётся большой, и под правило они не попадают.
    ///
    /// ⚠️ Растянутое НАСТОЯЩЕЕ слово не удаляется, а распрямляется: «Ну-у-у» → «Ну».
    /// Удалить его было бы потерей смысла, а оставить как есть — мусором в тексте.
    static func stripFillers(_ text: String) -> String {
        var out = ""
        var word = "", sep = ""
        var prevWord = ""
        var dropped = false
        var didDrop = false        // хоть один филлер убрали — только тогда нужна уборка
        var droppedWasUpper = false // убранный филлер был с заглавной
        var pendingCapital = false  // следующему слову нужна заглавная: филлер начинал предложение

        func flush() {
            guard !word.isEmpty else { return }
            // Цифры не трогаем вовсе: схлопывание повторов превращало «100» в «10».
            // Аббревиатуры из заглавных — тоже: «ИИ» сворачивалось в «и» и удалялось как филлер.
            let untouchable = word.contains { $0.isNumber }
                || (word.count >= 2 && word.allSatisfy { !$0.isLetter || $0.isUppercase })
            guard !untouchable else {
                // Заглавная тут ни при чём: число не капитализируется, аббревиатура и так
                // заглавная. Но флаг надо погасить, иначе он уедет на следующее слово.
                pendingCapital = false
                out += sep + word; prevWord = word; word = ""; sep = ""; dropped = false; return
            }
            let col = collapsed(word)
            let shrank = col.count < word.count
            // «5 мм» — это миллиметры, а не мычание. Число слева снимает подозрение.
            let afterNumber = prevWord.contains { $0.isNumber }
            // Требование длины нужно только растянутым звукам, и оно уже зашито в `shrank`:
            // свернувшееся слово по определению было длиннее. Безусловным филлерам («э», «хм»)
            // длина не нужна — одиночное «э» такой же мусор, как «э-э-э».
            let isFiller = !afterNumber && col.count <= 2
                && (fillerWords.contains(col) || (shrank && fillerSounds.contains(col)))

            if isFiller {
                // Разделитель ПЕРЕД филлером сохраняем и отдаём следующему слову, а тот, что
                // идёт после, пропускаем в цикле. Иначе съедаются оба и слова слипаются:
                // «проверка хмм всяких» давало «проверкався ких».
                dropped = true
                didDrop = true
                // Регистр филлера — признак того, что он стоял в начале предложения. Решение
                // принимается не здесь: разделитель, который достанется следующему слову,
                // ещё не выбран (см. pickSeparator).
                droppedWasUpper = word.first?.isUppercase == true
                word = ""
                return
            } else {
                // Растянутое настоящее слово распрямляем, регистр первой буквы сохраняем.
                // ⚠️ Распрямлять можно ТОЛЬКО короткие формы. Без ограничения на длину
                // схлопывание съедало бы двойные буквы в обычных словах: «коммуникации»
                // превратились бы в «комуникации».
                let stretched = shrank && stretchable.contains(col)
                var fixed = stretched ? restoreCase(col, like: word) : word
                if pendingCapital {
                    pendingCapital = false
                    fixed = capitalizedFirst(fixed)
                }
                out += sep + fixed
                prevWord = word
                dropped = false
            }
            word = ""; sep = ""
        }

        // При удалении филлера остаются ДВА разделителя — до него и после. Оставить надо
        // один, и именно тот, что несёт пунктуацию: «Ну, эээ, дальше» → «Ну, дальше», но
        // «Проверка ии. Сто» → «Проверка. Сто», а не «Проверка Сто» со склейкой предложений.
        var sepAfter = ""
        func pickSeparator() {
            // Приоритет у разделителя ДО филлера: там стоит конец предложения, а после
            // филлера обычно запятая, которой он был отделён. Иначе «Почему? А-а, как бы»
            // теряло вопросительный знак, превращаясь в «Почему, как бы».
            let hasPunct = { (t: String) in t.contains { $0.isPunctuation } }
            if !hasPunct(sep) && hasPunct(sepAfter) { sep = sepAfter }
            // Заглавная следующему слову — если филлер начинал предложение. Решать можно
            // только теперь: разделителей вокруг филлера два, а уцелел один, и именно он
            // говорит, кончилось ли предложение.
            //
            // ⚠️ Регистр САМОГО филлера — признак только в начале текста, где разделителя
            // слева нет вовсе. В середине он врёт: движок пишет филлер с заглавной как
            // отдельную реплику, и «их закрыли, Хмм, потом решили» давало «закрыли, Потом»
            // (живая строка из истории). Дальше решает только разделитель.
            if (out.isEmpty && droppedWasUpper) || endsSentence(sep) { pendingCapital = true }
            droppedWasUpper = false
            sepAfter = ""
            dropped = false
        }
        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "-" {
                if dropped { pickSeparator() }
                word.append(ch)
            } else {
                flush()
                if dropped { sepAfter.append(ch) } else { sep.append(ch) }
            }
        }
        if dropped { pickSeparator() }
        flush()
        // Хвостовые знаки после последнего слова: без этого терялась точка в конце фразы.
        out += sep
        // Уборка чинит следы удаления — повисшие запятые и сдвоенные пробелы. Если ничего не
        // удаляли, запускать её нельзя: она переформатировала бы чужую пунктуацию, например
        // склеивала «контрагентов. ..» в «контрагентов...», чего никто не просил.
        guard didDrop else { return out }
        return tidy(out)
    }

    /// Разделитель закрывает предложение — значит следующее слово начинает новое.
    private static func endsSentence(_ sep: String) -> Bool {
        sep.contains { ".!?…".contains($0) }
    }

    private static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first, first.isLowercase else { return s }
        return first.uppercased() + s.dropFirst()
    }

    private static func restoreCase(_ s: String, like original: String) -> String {
        guard let first = original.first, first.isUppercase else { return s }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Уборка после удаления: сдвоенные пробелы и повисшие знаки. Без неё «Ну, эээ, дальше»
    /// дало бы «Ну, , дальше» — заметно хуже исходного. Заглавную ставит не она, а разбор:
    /// там известно, какой разделитель уцелел (см. pickSeparator).
    private static func tidy(_ s: String) -> String {
        var t = s
        // Только следы удаления: сдвоенные пробелы и знак, оставшийся в начале строки.
        // Пунктуацию в остальном тексте НЕ трогаем — разделитель после филлера пропускается
        // при разборе, поэтому повисших запятых не остаётся, а чужие многоточия не наше дело.
        for (pattern, replacement) in [("[ \t]{2,}", " "), ("^[\\s,;:.!?…]+", "")] {
            t = t.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
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
    ///   английских слов. Костяк должен совпасть точно, плюс побуквенная близость ≥ 0.5.
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
            // Порог 0.5, а не 0.6 (macOS 0.9.18). Причина смены — живой промах: движок
            // написал `Depsic`, костяк совпал точно, а побуквенно вышло ровно 0.50, и термин
            // не починился. Прогон по всей истории (138 строк, тексты + сырые) при 0.5 не
            // изменил НИ ОДНОЙ строки против 0.6 — двадцать замен там и там, — а ловушки
            // держатся не порогом: «Greek»/«Groq» отсеиваются костяком (`grk` против `grq`,
            // `q` в `k` не сворачивается), «vice versa» — минимальной длиной костяка.
            hits = hits.filter { similarity(w, latinized($0)) >= 0.5 }
        }
        guard !hits.isEmpty else { return nil }
        // Несколько терминов с одним костяком — берём ближайший по длине к сказанному.
        return hits.min { abs($0.count - word.count) < abs($1.count - word.count) }
    }
}
