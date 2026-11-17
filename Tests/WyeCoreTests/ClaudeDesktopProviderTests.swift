import XCTest
@testable import WyeCore

final class ClaudeDesktopProviderTests: XCTestCase {
    var root: URL!
    var liveDir: URL!
    var storeDir: URL!
    var app: FakeAppControl!
    var provider: ClaudeDesktopProvider!

    override func setUp() {
        root = makeTempDir()
        liveDir = root.appendingPathComponent("Claude")
        storeDir = root.appendingPathComponent("Wye/desktop")
        app = FakeAppControl()
        provider = ClaudeDesktopProvider(liveDir: liveDir, storeDir: storeDir, app: app)
        write("personal-cookies", to: liveDir.appendingPathComponent("Cookies"))
        write("big-vm", to: liveDir.appendingPathComponent("vm_bundles/image"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private var liveCookies: String? { read(liveDir.appendingPathComponent("Cookies")) }

    /// Leaves "Personal" stored, and "Company" live.
    private func saveBothAccounts() throws {
        try provider.capture(as: "Personal")
        try provider.deactivate(current: "Personal")
        write("company-cookies", to: liveDir.appendingPathComponent("Cookies"))
        try provider.capture(as: "Company")
        app.events.removeAll()
    }

    func testDeactivateMovesProfileAsideAndLeavesFreshFolder() throws {
        try provider.capture(as: "Personal")
        try provider.deactivate(current: "Personal")
        XCTAssertEqual(read(storeDir.appendingPathComponent("Personal/Cookies")), "personal-cookies")
        XCTAssertNil(liveCookies)
        XCTAssertTrue(exists(liveDir))
        XCTAssertEqual(app.events, ["quit", "launch"])
    }

    func testSharedDownloadsFollowTheLiveFolder() throws {
        try provider.capture(as: "Personal")
        try provider.deactivate(current: "Personal")
        XCTAssertEqual(read(liveDir.appendingPathComponent("vm_bundles/image")), "big-vm")
        XCTAssertFalse(exists(storeDir.appendingPathComponent("Personal/vm_bundles")))
    }

    func testActivateSwapsFolders() throws {
        try saveBothAccounts()
        try provider.activate("Personal", replacing: "Company")
        XCTAssertEqual(liveCookies, "personal-cookies")
        XCTAssertEqual(read(storeDir.appendingPathComponent("Company/Cookies")), "company-cookies")
        XCTAssertFalse(exists(storeDir.appendingPathComponent("Personal")))
        XCTAssertEqual(read(liveDir.appendingPathComponent("vm_bundles/image")), "big-vm")
        XCTAssertEqual(app.events, ["quit", "launch"])
    }

    func testDoesNotQuitWhenAppIsNotRunning() throws {
        try saveBothAccounts()
        app.running = false
        try provider.activate("Personal", replacing: "Company")
        XCTAssertEqual(app.events, ["launch"])
    }

    func testRefusesToSwapWhileAppWillNotQuit() throws {
        try saveBothAccounts()
        app.quitSucceeds = false
        XCTAssertThrowsError(try provider.activate("Personal", replacing: "Company"))
        XCTAssertEqual(liveCookies, "company-cookies")
        XCTAssertTrue(exists(storeDir.appendingPathComponent("Personal")))
    }

    func testRollsBackWhenIncomingFolderCannotBeMoved() throws {
        try saveBothAccounts()
        var calls = 0
        provider.move = { from, to in
            calls += 1
            if calls == 2 { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.moveItem(at: from, to: to)
        }
        XCTAssertThrowsError(try provider.activate("Personal", replacing: "Company"))
        XCTAssertEqual(liveCookies, "company-cookies")
        XCTAssertEqual(read(storeDir.appendingPathComponent("Personal/Cookies")), "personal-cookies")
        XCTAssertFalse(exists(storeDir.appendingPathComponent("Company")))
    }

    func testRefusesWhenLiveFolderBelongsToAnotherProfile() throws {
        try saveBothAccounts()
        XCTAssertThrowsError(try provider.activate("Personal", replacing: "SomethingElse"))
        XCTAssertEqual(liveCookies, "company-cookies")
    }

    func testRefusesWhenLiveFolderWasNeverSaved() throws {
        try provider.capture(as: "Personal")
        try provider.deactivate(current: "Personal")
        write("unsaved-cookies", to: liveDir.appendingPathComponent("Cookies"))
        XCTAssertThrowsError(try provider.activate("Personal", replacing: nil))
        XCTAssertEqual(liveCookies, "unsaved-cookies")
    }

    func testRefusesWhenStoredFolderMarkerDoesNotMatch() throws {
        try saveBothAccounts()
        try FileManager.default.moveItem(
            at: storeDir.appendingPathComponent("Personal"),
            to: storeDir.appendingPathComponent("Impostor"))
        XCTAssertThrowsError(try provider.activate("Impostor", replacing: "Company"))
        XCTAssertEqual(liveCookies, "company-cookies")
    }

    func testCannotSaveLiveFolderUnderASecondName() throws {
        try provider.capture(as: "Personal")
        XCTAssertThrowsError(try provider.capture(as: "Other"))
    }

    func testActivateWorksWhenNothingIsLive() throws {
        try provider.capture(as: "Personal")
        try provider.deactivate(current: "Personal")
        try FileManager.default.removeItem(at: liveDir.appendingPathComponent("vm_bundles"))
        try provider.activate("Personal", replacing: nil)
        XCTAssertEqual(liveCookies, "personal-cookies")
    }
}

final class RunningAppControlTests: XCTestCase {
    let bundle = "/Applications/Claude.app"

    func testHelperProcessCountsAsStillRunning() {
        let ps = """
        /usr/bin/ssh
        /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper
        """
        XCTAssertTrue(RunningAppControl.hasAppProcess(psOutput: ps, bundlePath: bundle))
    }

    func testBrowserBridgeStartedByChromeDoesNotCount() {
        let ps = """
        /Applications/Claude.app/Contents/Helpers/chrome-native-host
        /Applications/Claude.appendix/Contents/MacOS/Other
        """
        XCTAssertFalse(RunningAppControl.hasAppProcess(psOutput: ps, bundlePath: bundle))
    }
}
