import XCTest
@testable import InstantSwitcher

final class ShortcutEngineTests: XCTestCase {
    var locator: FakeSpaceLocator!
    var core: FakeISSCore!
    var activator: FakeAppActivator!
    var engine: ShortcutEngine!

    override func setUp() {
        locator = FakeSpaceLocator()
        core = FakeISSCore()
        activator = FakeAppActivator()
        engine = ShortcutEngine(locator: locator, core: core, activator: activator)
    }

    func testSpaceBindingCallsIndex() {
        engine.fire(.space(SpaceBinding(id: UUID(), spaceIndex: 4, label: "Four")))
        XCTAssertEqual(core.calls, [.index(4)])
        XCTAssertTrue(activator.activateCalls.isEmpty)
    }

    func testAppBindingJumpsToSpaceThenActivates() {
        locator.byBundleID["com.slack"] = 3
        activator.running["com.slack"] = true
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertEqual(core.calls, [.index(3)])
        XCTAssertEqual(activator.activateCalls, ["com.slack"])
    }

    func testAppBindingWithUnknownSpaceSkipsISSButStillActivates() {
        activator.running["com.slack"] = true
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertTrue(core.calls.isEmpty)
        XCTAssertEqual(activator.activateCalls, ["com.slack"])
    }

    func testAppBindingLaunchesWhenNotRunning() {
        activator.running["com.slack"] = false
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertEqual(activator.launchCalls, ["com.slack"])
    }

    func testSystemOverrideLeftCallsLeft() {
        engine.systemOverride(.left)
        XCTAssertEqual(core.calls, [.left])
    }

    func testSystemOverrideRightCallsRight() {
        engine.systemOverride(.right)
        XCTAssertEqual(core.calls, [.right])
    }

    func testSystemOverrideIndex() {
        engine.systemOverride(.index(7))
        XCTAssertEqual(core.calls, [.index(7)])
    }
}
