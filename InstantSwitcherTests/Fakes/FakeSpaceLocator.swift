import Foundation
@testable import InstantSwitcher

final class FakeSpaceLocator: SpaceLocating {
    var currentIndex: Int? = 1
    var byBundleID: [String: Int] = [:]
    private(set) var lookups: [String] = []

    func currentSpaceIndex() -> Int? { currentIndex }

    func spaceIndex(forBundleID bundleID: String) -> Int? {
        lookups.append(bundleID)
        return byBundleID[bundleID]
    }
}
