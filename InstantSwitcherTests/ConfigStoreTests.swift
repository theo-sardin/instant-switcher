import XCTest
@testable import InstantSwitcher

final class ConfigStoreTests: XCTestCase {
    var tmpDir: URL!

    override func setUp() {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instantswitcher-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testLoadReturnsDefaultWhenFileMissing() {
        let store = ConfigStore(directory: tmpDir)
        XCTAssertEqual(store.load(), Config.default)
    }

    func testSaveThenLoadRoundTrip() throws {
        let store = ConfigStore(directory: tmpDir)
        var cfg = Config.default
        cfg.bindings = [.space(SpaceBinding(id: UUID(), spaceIndex: 2, label: "Two"))]
        try store.save(cfg)
        XCTAssertEqual(store.load(), cfg)
    }

    func testUnknownSchemaIsBackedUpAndDefaultsReturned() throws {
        let path = tmpDir.appendingPathComponent("config.json")
        let bad = #"{"schemaVersion":999,"bindings":[],"systemOverrides":{"arrows":true,"digits":false},"launchAtLogin":false}"#
        try bad.write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(directory: tmpDir)
        let loaded = store.load()
        XCTAssertEqual(loaded, Config.default)
        let contents = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertTrue(contents.contains { $0.hasPrefix("config.json.backup-") })
    }

    func testCorruptFileIsBackedUpAndDefaultsReturned() throws {
        let path = tmpDir.appendingPathComponent("config.json")
        try "not json".write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(directory: tmpDir)
        XCTAssertEqual(store.load(), Config.default)
        let contents = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertTrue(contents.contains { $0.hasPrefix("config.json.backup-") })
    }
}
