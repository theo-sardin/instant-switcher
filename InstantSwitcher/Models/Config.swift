import Foundation

struct SystemOverrides: Codable, Hashable {
    var arrows: Bool
    var digits: Bool
    /// When true, ISS intercepts all native Dock-swipe gestures (trackpad
    /// swipes AND the synthetic swipe macOS performs internally when Cmd+Tab
    /// activates an app on another space), replacing them with instant
    /// switches.
    var swipe: Bool

    static let `default` = SystemOverrides(arrows: true, digits: false, swipe: false)

    init(arrows: Bool, digits: Bool, swipe: Bool) {
        self.arrows = arrows; self.digits = digits; self.swipe = swipe
    }
    // Decoder keeps old configs (missing `swipe` key) loadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.arrows = try c.decodeIfPresent(Bool.self, forKey: .arrows) ?? true
        self.digits = try c.decodeIfPresent(Bool.self, forKey: .digits) ?? false
        self.swipe = try c.decodeIfPresent(Bool.self, forKey: .swipe) ?? false
    }
    private enum CodingKeys: String, CodingKey { case arrows, digits, swipe }
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
