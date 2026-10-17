import XCTest
@testable import MagpieKit

final class ProfileTests: XCTestCase {
    func testConfiguration() {
        var profile = ProfileConfig(name: "演示", gatewayURL: "https://example.ts.net")
        XCTAssertFalse(profile.isInsecure)
        XCTAssertEqual(profile.sshPort, 22)
        XCTAssertEqual(profile.refreshInterval, 20)
        XCTAssertEqual(profile.webPort, 80)
        XCTAssertTrue(profile.validate().isEmpty)
        profile.webURL = "https://example.ts.net"
        XCTAssertEqual(profile.webPort, 443)
        profile.webURL = "http://example.ts.net:8080"
        XCTAssertEqual(profile.webPort, 8080)
        XCTAssertTrue(profile.isInsecure)
        for url in ["not a url", "ftp://example.ts.net", "https:///", "https://example.ts.net?key=demo", "https://example.ts.net:99999"] {
            profile.gatewayURL = url
            XCTAssertFalse(profile.validate().isEmpty, url)
        }
    }

    func testStoreRoundTripAndSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("profiles.json")
        var store = ProfileStore(fileURL: file)
        try store.load()
        XCTAssertTrue(store.profiles.isEmpty)
        let first = ProfileConfig(name: "演示一", gatewayURL: "https://example.ts.net")
        let second = ProfileConfig(name: "演示二", gatewayURL: "http://100.64.0.1")
        store.add(first); store.add(second); store.select(id: second.id)
        try store.save()
        var restored = ProfileStore(fileURL: file)
        try restored.load()
        XCTAssertEqual(restored.profiles, [first, second])
        XCTAssertEqual(restored.selectedID, second.id)
        restored.select(id: UUID())
        XCTAssertEqual(restored.selectedID, second.id)
        restored.remove(id: second.id)
        XCTAssertEqual(restored.selectedID, first.id)
        restored.remove(id: first.id)
        XCTAssertNil(restored.selectedID)
    }

    func testSecrets() async throws {
        let store = InMemorySecretStore()
        let id = UUID()
        for field in SecretField.allCases {
            let account = field.account(profileID: id)
            XCTAssertEqual(account, "magpie-ios.\(id.uuidString).\(field.rawValue)")
            await store.set("demo", account: account)
            let value = await store.get(account: account)
            XCTAssertEqual(value, "demo")
            await store.delete(account: account)
            let removed = await store.get(account: account)
            XCTAssertNil(removed)
        }
    }
}
