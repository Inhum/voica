// Помощник локализации. Строки лежат в Resources/<lang>.lproj/Localizable.strings.
// Язык выбирается автоматически по системным настройкам (en — база, ru — перевод).

import Foundation

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}
