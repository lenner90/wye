import XCTest
@testable import WyeCore

/// Runs against the real login Keychain, using a throwaway item that is removed afterwards.
final class SecurityCLIKeychainTests: XCTestCase {
    let keychain = SecurityCLIKeychain()
    let service = "Wye.selftest"
    let account = NSUserName()

    override func tearDown() {
        try? keychain.delete(service: service, account: account)
    }

    func testRoundTripsAJSONSecret() throws {
        let secret = "{\"claudeAiOauth\":{\"accessToken\":\"abc 123\",\"scopes\":[\"a\",\"b\"]}}"
        try keychain.write(service: service, account: account, value: secret)
        XCTAssertEqual(try keychain.read(service: service, account: account), secret)
    }

    func testOverwritesExistingValue() throws {
        try keychain.write(service: service, account: account, value: "one")
        try keychain.write(service: service, account: account, value: "two")
        XCTAssertEqual(try keychain.read(service: service, account: account), "two")
    }

    func testMissingItemReadsAsNil() throws {
        XCTAssertNil(try keychain.read(service: service, account: account))
    }

    func testDeleteRemovesItemAndToleratesMissing() throws {
        try keychain.write(service: service, account: account, value: "one")
        try keychain.delete(service: service, account: account)
        XCTAssertNil(try keychain.read(service: service, account: account))
        XCTAssertNoThrow(try keychain.delete(service: service, account: account))
    }

    func testRefusesSecretTooLongForStdinInsteadOfTruncating() throws {
        try keychain.write(service: service, account: account, value: "short")
        let long = String(repeating: "a", count: 3000)
        XCTAssertThrowsError(try keychain.write(service: service, account: account, value: long)) {
            XCTAssertEqual($0 as? WyeError, .secretTooLong)
        }
        XCTAssertEqual(try keychain.read(service: service, account: account), "short")
    }
}
