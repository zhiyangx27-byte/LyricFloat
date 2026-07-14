import Foundation

actor JSONFileStore<Value: Codable & Sendable> {
    private let fileURL: URL

    init(fileName: String) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("LyricFloat", isDirectory: true)
        fileURL = directory.appendingPathComponent(fileName)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load(default defaultValue: Value) -> Value {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaultValue
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            AppLog.storage.error("Unable to read persisted data: \(error.localizedDescription, privacy: .public)")
            return defaultValue
        }

        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            preserveCorruptFile()
            AppLog.storage.error("Preserved corrupt persisted data: \(error.localizedDescription, privacy: .public)")
            return defaultValue
        }
    }

    func save(_ value: Value) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pretty.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }

    private func preserveCorruptFile() {
        let backupURL = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
