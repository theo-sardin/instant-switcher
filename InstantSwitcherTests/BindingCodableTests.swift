import XCTest
@testable import InstantSwitcher

final class BindingCodableTests: XCTestCase {
    func testAppBindingRoundTrip() throws {
        let id = UUID()
        let original = Binding.app(AppBinding(
            id: id,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            displayName: "Slack",
            iconPath: "/Applications/Slack.app"
        ))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Binding.self, from: data)
        XCTAssertEqual(decoded.id, id)
        if case let .app(b) = decoded {
            XCTAssertEqual(b.bundleIdentifier, "com.tinyspeck.slackmacgap")
            XCTAssertEqual(b.displayName, "Slack")
        } else {
            XCTFail("expected .app case")
        }
    }

    func testSpaceBindingRoundTrip() throws {
        let id = UUID()
        let original = Binding.space(SpaceBinding(id: id, spaceIndex: 3, label: "Comms"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Binding.self, from: data)
        XCTAssertEqual(decoded.id, id)
        if case let .space(b) = decoded {
            XCTAssertEqual(b.spaceIndex, 3)
            XCTAssertEqual(b.label, "Comms")
        } else {
            XCTFail("expected .space case")
        }
    }

    func testConfigRoundTrip() throws {
        let cfg = Config(
            schemaVersion: 1,
            bindings: [
                .space(SpaceBinding(id: UUID(), spaceIndex: 1, label: "One"))
            ],
            systemOverrides: SystemOverrides(arrows: true, digits: false),
            launchAtLogin: true
        )
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.bindings.count, 1)
        XCTAssertTrue(decoded.systemOverrides.arrows)
        XCTAssertFalse(decoded.systemOverrides.digits)
        XCTAssertTrue(decoded.launchAtLogin)
    }
}
