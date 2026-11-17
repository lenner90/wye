import XCTest
@testable import WyeCore

final class SwitcherTests: XCTestCase {
    var root: URL!
    var config: URL!
    var secrets: FakeSecretStore!
    var switcher: Switcher!
    let cli = "claude-cli"

    private func makeSwitcher() -> Switcher {
        let provider = ClaudeCLIProvider(
            configURL: config, secrets: secrets, account: "me",
            supportDir: root.appendingPathComponent("support"), runningSessions: { 0 })
        return Switcher(stateURL: root.appendingPathComponent("support/state.json"), providers: [provider])
    }

    private func logIn(token: String, uuid: String) {
        secrets.items["Claude Code-credentials|me"] = token
        write("{\"oauthAccount\": {\"accountUuid\": \"\(uuid)\"}}", to: config)
    }

    override func setUp() {
        root = makeTempDir()
        config = root.appendingPathComponent("claude.json")
        secrets = FakeSecretStore()
        logIn(token: "personal", uuid: "u-p")
        switcher = makeSwitcher()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testSavingMakesProfileActive() throws {
        try switcher.saveCurrent(cli, as: "Personal")
        let state = switcher.state().providers[cli]
        XCTAssertEqual(state?.profiles, ["Personal"])
        XCTAssertEqual(state?.active, "Personal")
    }

    func testRejectsUnsafeProfileNames() {
        for bad in ["", "  ", "a/b", "a\"b", "..", String(repeating: "x", count: 41)] {
            XCTAssertThrowsError(try switcher.saveCurrent(cli, as: bad), "accepted \(bad)")
        }
    }

    func testRejectsReusingAnotherProfilesName() throws {
        try switcher.saveCurrent(cli, as: "Personal")
        try switcher.addAccount(cli)
        logIn(token: "company", uuid: "u-c")
        XCTAssertThrowsError(try switcher.saveCurrent(cli, as: "Personal"))
        XCTAssertEqual(secrets.items["Wye.claude-cli.Personal|me"], "personal")
    }

    func testAddAccountLogsOutAndClearsActive() throws {
        try switcher.saveCurrent(cli, as: "Personal")
        try switcher.addAccount(cli)
        XCTAssertNil(switcher.state().providers[cli]?.active)
        XCTAssertNil(secrets.items["Claude Code-credentials|me"])
    }

    func testAddAccountRefusesWhenCurrentLoginIsUnsaved() {
        XCTAssertThrowsError(try switcher.addAccount(cli))
        XCTAssertEqual(secrets.items["Claude Code-credentials|me"], "personal")
    }

    func testSwitchingBetweenTwoAccounts() throws {
        try switcher.saveCurrent(cli, as: "Personal")
        try switcher.addAccount(cli)
        logIn(token: "company", uuid: "u-c")
        try switcher.saveCurrent(cli, as: "Company")

        try switcher.switchTo(cli, profile: "Personal")
        XCTAssertEqual(secrets.items["Claude Code-credentials|me"], "personal")
        XCTAssertEqual(switcher.state().providers[cli]?.active, "Personal")

        try switcher.switchTo(cli, profile: "Company")
        XCTAssertEqual(secrets.items["Claude Code-credentials|me"], "company")
        XCTAssertEqual(switcher.state().providers[cli]?.profiles, ["Personal", "Company"])
    }

    func testFailedSwitchKeepsActiveUnchanged() throws {
        try switcher.saveCurrent(cli, as: "Personal")
        XCTAssertThrowsError(try switcher.switchTo(cli, profile: "Ghost"))
        XCTAssertEqual(switcher.state().providers[cli]?.active, "Personal")
    }

    func testStateSurvivesRestartAndHoldsNoSecrets() throws {
        try switcher.saveCurrent(cli, as: "Personal")
        XCTAssertEqual(makeSwitcher().state().providers[cli]?.active, "Personal")
        let raw = read(root.appendingPathComponent("support/state.json"))!
        XCTAssertFalse(raw.contains("personal"))
    }
}
