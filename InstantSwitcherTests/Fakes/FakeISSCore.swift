import Foundation
@testable import InstantSwitcher

enum FakeISSCall: Equatable {
    case left
    case right
    case index(Int)
}

final class FakeISSCore: ISSInvoking {
    var isInitialized: Bool = true
    var ensureResult: Bool = true
    var info: ISSSpaceStatus?
    private(set) var calls: [FakeISSCall] = []

    @discardableResult
    func ensureInitialized() -> Bool { ensureResult }

    func left() { calls.append(.left) }
    func right() { calls.append(.right) }
    func index(_ oneBased: Int) { calls.append(.index(oneBased)) }
    func currentSpaceInfo() -> ISSSpaceStatus? { info }
    var swipeOverride: Bool = false
    func setSwipeOverride(_ on: Bool) { swipeOverride = on }
    private(set) var externalSpaceChangeCount = 0
    func noteExternalSpaceChange() { externalSpaceChangeCount += 1 }
}
