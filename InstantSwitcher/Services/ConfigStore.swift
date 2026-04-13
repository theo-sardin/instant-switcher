import Foundation
import os

final class ConfigStore {
    static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("InstantSwitcher", isDirectory: true)
    }()

    private let directory: URL
    private let fileURL: URL
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "config")

    init(directory: URL = ConfigStore.defaultDirectory) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load() -> Config {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .default }
        do {
            let data = try Data(contentsOf: fileURL)
            let cfg = try JSONDecoder().decode(Config.self, from: data)
            guard cfg.schemaVersion == Config.currentSchemaVersion else {
                log.error("Unknown schema version \(cfg.schemaVersion); backing up.")
                backup()
                return .default
            }
            return cfg
        } catch {
            log.error("Failed to decode config: \(error.localizedDescription); backing up.")
            backup()
            return .default
        }
    }

    func save(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }

    private func backup() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = directory.appendingPathComponent("config.json.backup-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}
