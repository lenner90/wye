import XCTest
@testable import WyeCore

final class ClaudeCLIProviderTests: XCTestCase {
    var root: URL!
    var config: URL!
    var secrets: FakeSecretStore!
    var provider: ClaudeCLIProvider!
    let live = "Claude Code-credentials"

    func configText(email: String, uuid: String) -> String {
        """
        {
          "numStartups": 12,
          "oauthAccount": {
            "accountUuid": "\(uuid)",
            "emailAddress": "\(email)"
          },
          "userID": "keep-me"
        }
        """
    }

    override func setUp() {
        root = makeTempDir()
        config = root.appendingPathComponent("claude.json")
        secrets = FakeSecretStore()
        provider = ClaudeCLIProvider(
            configURL: config,
            secrets: secrets,
            account: "me",
            supportDir: root.appendingPathComponent("support"),
            runningSessions: { 0 })
        write(configText(email: "p@home.com", uuid: "uuid-personal"), to: config)
        secrets.items["\(live)|me"] = "personal-token-1"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Leaves "Personal" saved, and "Company" saved and live.
    private func saveBothAccounts() throws {
        try provider.capture(as: "Personal")
        try provider.deactivate(current: "Personal")
        secrets.items["\(live)|me"] = "company-token-1"
        write(configText(email: "c@corp.com", uuid: "uuid-company"), to: config)
        try provider.capture(as: "Company")
    }

    func testShowsEmailOfLiveAccount() {
        XCTAssertEqual(provider.currentAccountLabel(), "p@home.com")
    }

    func testCaptureStoresTokenUnderProfile() throws {
        try provider.capture(as: "Personal")
        XCTAssertEqual(secrets.items["Wye.claude-cli.Personal|me"], "personal-token-1")
        XCTAssertEqual(secrets.items["\(live)|me"], "personal-token-1")
    }

    func testCaptureWithoutLoginThrows() {
        secrets.items.removeAll()
        XCTAssertThrowsError(try provider.capture(as: "Personal"))
    }

    func testDeactivateLogsOutButKeepsSavedProfile() throws {
        try provider.capture(as: "Personal")
        try provider.deactivate(current: "Personal")
        XCTAssertNil(secrets.items["\(live)|me"])
        XCTAssertNil(provider.currentAccountLabel())
        XCTAssertEqual(secrets.items["Wye.claude-cli.Personal|me"], "personal-token-1")
        XCTAssertTrue(read(config)!.contains("\"userID\": \"keep-me\""))
    }

    func testActivateRestoresTokenAndAccountBlock() throws {
        try saveBothAccounts()
        try provider.activate("Personal", replacing: "Company")
        XCTAssertEqual(secrets.items["\(live)|me"], "personal-token-1")
        XCTAssertEqual(read(config), configText(email: "p@home.com", uuid: "uuid-personal"))
    }

    func testActivateSavesRefreshedTokenOfOutgoingAccount() throws {
        try saveBothAccounts()
        secrets.items["\(live)|me"] = "company-token-2-refreshed"
        try provider.activate("Personal", replacing: "Company")
        XCTAssertEqual(
            secrets.items["Wye.claude-cli.Company|me"], "company-token-2-refreshed")
    }

    func testActivateRefusesWhenLiveLoginWasNeverSaved() throws {
        try provider.capture(as: "Personal")
        secrets.items["\(live)|me"] = "someone-else"
        let before = read(config)
        XCTAssertThrowsError(try provider.activate("Personal", replacing: nil))
        XCTAssertEqual(secrets.items["\(live)|me"], "someone-else")
        XCTAssertEqual(read(config), before)
    }

    func testActivateUnknownProfileThrowsAndChangesNothing() throws {
        try provider.capture(as: "Personal")
        XCTAssertThrowsError(try provider.activate("Ghost", replacing: "Personal"))
        XCTAssertEqual(secrets.items["\(live)|me"], "personal-token-1")
    }

    func testRefusesToOverwriteProfileWithADifferentAccount() throws {
        try saveBothAccounts()
        // Wye believes "Personal" is live, but the user logged in to Company by hand.
        XCTAssertThrowsError(try provider.capture(as: "Personal"))
        XCTAssertEqual(secrets.items["Wye.claude-cli.Personal|me"], "personal-token-1")
    }

    func testFailedLiveWriteLeavesConfigUntouched() throws {
        try saveBothAccounts()
        let before = read(config)
        secrets.failWritesTo = live
        XCTAssertThrowsError(try provider.activate("Personal", replacing: "Company"))
        XCTAssertEqual(read(config), before)
    }

    func testConfigIsBackedUpBeforeBeingChanged() throws {
        try saveBothAccounts()
        let backups = root.appendingPathComponent("support/backups")
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertFalse(files.isEmpty)
        let first = backups.appendingPathComponent(files.sorted()[0])
        XCTAssertEqual(read(first), configText(email: "p@home.com", uuid: "uuid-personal"))
    }

    func testConfigKeepsOwnerOnlyPermissions() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        try saveBothAccounts()
        try provider.activate("Personal", replacing: "Company")
        let perms = try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions]
        XCTAssertEqual((perms as? NSNumber)?.intValue, 0o600)
    }

    func testWarnsWhenSessionsAreRunning() {
        let busy = ClaudeCLIProvider(
            configURL: config, secrets: secrets, account: "me",
            supportDir: root.appendingPathComponent("support"), runningSessions: { 2 })
        XCTAssertNotNil(busy.runningWarning())
        XCTAssertNil(provider.runningWarning())
    }

    func testCountsOnlyTerminalClaudeProcesses() {
        let ps = """
        /Users/me/.local/bin/claude
        /Users/me/Library/Application Support/Claude/claude-code/2.1.325/claude
        /Applications/Claude.app/Contents/MacOS/Claude
        /usr/bin/ssh
        claude
        """
        XCTAssertEqual(ClaudeCLIProvider.countCLISessions(psOutput: ps), 2)
    }
}
