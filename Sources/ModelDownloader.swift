// Загрузчик локальной модели: качает .zip с .mlpackage (release-ассет GitHub),
// проверяет SHA-256 и распаковывает в Application Support/models.
//
// Синглтон: скачивание переживает закрытие окна настроек. Прогресс и завершение
// отдаются коллбэками на главном потоке — UI подписывается на них один раз.

import CryptoKit
import Foundation

final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()

    /// Откуда качаем. $VOICA_GIGAAM_URL — dev-переопределение источника (контрольная сумма
    /// проверяется всегда; другую модель в dev подставляют через $VOICA_GIGAAM, без загрузчика).
    static var downloadURL: URL {
        if let dev = ProcessInfo.processInfo.environment["VOICA_GIGAAM_URL"],
           let url = URL(string: dev) { return url }
        return URL(string:
            "https://github.com/Inhum/voica/releases/download/gigaam-v3-e2e/gigaam_v3_e2e.mlpackage.zip")!
    }

    /// SHA-256 архива с моделью (release-ассет). Пересчитать при замене модели:
    /// shasum -a 256 gigaam_v3_e2e.mlpackage.zip
    static let expectedSHA256 = "129a1ca6047ee324fa1634aa7f59f32373a12683d949559b96580c497d58f36d"

    enum Outcome {
        case success
        case cancelled
        case failure(String)   // человекочитаемое описание
    }

    private(set) var isDownloading = false
    var onProgress: ((Double) -> Void)?      // 0…1, главный поток
    var onFinish: ((Outcome) -> Void)?       // главный поток

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    func start() {
        guard !isDownloading else { return }
        isDownloading = true
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        task = s.downloadTask(with: Self.downloadURL)
        task?.resume()
    }

    func cancel() {
        task?.cancel()   // завершение придёт в didCompleteWithError с NSURLErrorCancelled
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.onProgress?(p) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // location живёт только внутри этого коллбэка — сразу перекладываем.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voica-model-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw NSError(domain: "Voica", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: L("model.err.http", http.statusCode)])
            }
            try FileManager.default.moveItem(at: location, to: tmp)
            guard try Self.sha256Hex(of: tmp) == Self.expectedSHA256 else {
                throw NSError(domain: "Voica", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: L("model.err.checksum")])
            }
            try Self.install(zip: tmp)
            finish(.success)
        } catch {
            finish(.failure(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }   // успех уже обработан в didFinishDownloadingTo
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        finish(cancelled ? .cancelled : .failure(error.localizedDescription))
    }

    private func finish(_ outcome: Outcome) {
        // Всё состояние (isDownloading, session) живёт на главном потоке — UI читает его оттуда.
        DispatchQueue.main.async {
            guard self.isDownloading else { return }   // защита от двойного завершения
            self.isDownloading = false
            self.session?.finishTasksAndInvalidate()
            self.session = nil
            self.task = nil
            self.onFinish?(outcome)
        }
    }

    // MARK: - Проверка и установка

    /// SHA-256 файла потоково (файл ~420 МБ — не читаем целиком в память).
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Распаковывает zip в каталог (через системный ditto — зависимостей не добавляем).
    static func extract(zip: URL, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "Voica", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: L("model.err.unzip")])
        }
    }

    /// Распаковка в Application Support/models + чистка устаревшего скомпилированного кэша.
    private static func install(zip: URL) throws {
        let dir = Store.appSupportDir().appendingPathComponent("models", isDirectory: true)
        try extract(zip: zip, to: dir)
        let pkg = dir.appendingPathComponent("gigaam_v3_e2e.mlpackage")
        guard FileManager.default.fileExists(atPath: pkg.path) else {
            throw NSError(domain: "Voica", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: L("model.err.missing")])
        }
        // старый .mlmodelc мог остаться от прежней модели — иначе он затенит новую
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("gigaam_v3_e2e.mlmodelc"))
    }

    // MARK: - Установленная модель на диске

    static func modelsDir() -> URL {
        Store.appSupportDir().appendingPathComponent("models", isDirectory: true)
    }

    /// Сколько занимают модель и её скомпилированный кэш. 0 — не установлена.
    static func installedSizeBytes() -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: modelsDir(), includingPropertiesForKeys: [.fileSizeKey],
                                     options: [], errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    /// Удаляет модель вместе со скомпилированным кэшем (каталог models целиком).
    static func deleteInstalledModel() {
        try? FileManager.default.removeItem(at: modelsDir())
        LocalSTT.shared.unload()   // и из ОЗУ тоже
    }
}
