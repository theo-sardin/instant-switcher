import Foundation

struct SystemOverrides: Codable, Hashable {
    var arrows: Bool
    var digits: Bool

    static let `default` = SystemOverrides(arrows: true, digits: false)
}

struct Config: Codable, Hashable {
    var schemaVersion: Int
    var bindings: [Binding]
    var systemOverrides: SystemOverrides
    var launchAtLogin: Bool

    static let currentSchemaVersion = 1

    static let `default` = Config(
        schemaVersion: currentSchemaVersion,
        bindings: [],
        systemOverrides: .default,
        launchAtLogin: false
    )
}
