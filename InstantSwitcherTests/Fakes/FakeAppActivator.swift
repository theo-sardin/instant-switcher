import Foundation
@testable import InstantSwitcher

final class FakeAppActivator: AppActivating {
    var running: [String: Bool] = [:]
    private(set) var launchCalls: [String] = []
    private(set) var activateCalls: [String] = []

    func isRunning(bundleID: String) -> Bool { running[bundleID] ?? false }
    func activate(bundleID: String) { activateCalls.append(bundleID) }
    func launch(bundleID: String) { launchCalls.append(bundleID) }
}
