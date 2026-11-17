import AppKit
import Foundation

public protocol AppControl {
    func isRunning() -> Bool
    /// Asks the app to quit and waits. Returns false if it is still running afterwards.
    func quit() -> Bool
    func launch()
}

/// Switches the account of the Claude desktop app by swapping its whole data folder.
/// Folders are only ever renamed, never deleted or copied.
public final class ClaudeDesktopProvider: AccountProvider {
    public let id = "claude-desktop"
    public let displayName = "Claude Desktop"

    static let markerName = ".wye-profile"
    /// Large downloads that are not tied to an account; they follow the live folder.
    static let sharedItems = ["vm_bundles", "claude-code", "claude-code-vm"]

    private let liveDir: URL
    private let storeDir: URL
    private let app: AppControl
    private let fm = FileManager.default
    /// Replaceable so tests can make a move fail.
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public init(liveDir: URL, storeDir: URL, app: AppControl) {
        self.liveDir = liveDir
        self.storeDir = storeDir
        self.app = app
    }

    public static func live(supportDir: URL) -> ClaudeDesktopProvider {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ClaudeDesktopProvider(
            liveDir: appSupport.appendingPathComponent("Claude"),
            storeDir: supportDir.appendingPathComponent("desktop"),
            app: RunningAppControl(bundleID: "com.anthropic.claudefordesktop"))
    }

    // MARK: AccountProvider

    public func currentAccountLabel() -> String? { nil }

    public func runningWarning() -> String? {
        app.isRunning()
            ? "Claude will quit and reopen. Open chats and Code sessions in the app will be closed."
            : nil
    }

    public func hasLiveLogin() -> Bool { !accountItems(in: liveDir).isEmpty }

    public func capture(as profile: String) throws {
        guard hasLiveLogin() else { throw WyeError.noLiveLogin }
        if let existing = marker(in: liveDir), existing != profile {
            throw WyeError.alreadySaved(as: existing)
        }
        try Data(profile.utf8).write(to: liveDir.appendingPathComponent(Self.markerName))
    }

    public func activate(_ target: String, replacing current: String?) throws {
        let incoming = storeDir.appendingPathComponent(target)
        guard fm.fileExists(atPath: incoming.path) else { throw WyeError.profileMissing(target) }
        guard marker(in: incoming) == target else {
            throw WyeError.markerMismatch("stored folder \"\(target)\"")
        }
        let outgoing = try outgoingFolder(for: current)
        try quitIfRunning()

        if let outgoing {
            try move(liveDir, outgoing)
            do {
                try move(incoming, liveDir)
            } catch {
                try? move(outgoing, liveDir)
                throw error
            }
            moveSharedItems(from: outgoing, to: liveDir)
        } else {
            // Nothing account-specific is live: at most shared downloads in an otherwise empty folder.
            moveSharedItems(from: liveDir, to: incoming)
            try removeIfEmpty(liveDir)
            try move(incoming, liveDir)
        }
        app.launch()
    }

    public func deactivate(current: String) throws {
        guard let outgoing = try outgoingFolder(for: current) else { return }
        try quitIfRunning()
        try move(liveDir, outgoing)
        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)
        moveSharedItems(from: outgoing, to: liveDir)
        app.launch()
    }

    // MARK: Internals

    /// Where the live folder should be put away, or nil when there is nothing to put away.
    /// Throws rather than risk mixing up or losing a login.
    private func outgoingFolder(for current: String?) throws -> URL? {
        guard hasLiveLogin() else { return nil }
        guard let current else { throw WyeError.unsavedLogin }
        guard marker(in: liveDir) == current else {
            throw WyeError.markerMismatch("live folder is not \"\(current)\"")
        }
        let outgoing = storeDir.appendingPathComponent(current)
        guard !fm.fileExists(atPath: outgoing.path) else {
            throw WyeError.markerMismatch("a stored folder \"\(current)\" already exists")
        }
        try fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
        return outgoing
    }

    private func quitIfRunning() throws {
        if app.isRunning(), !app.quit() { throw WyeError.appWouldNotQuit }
    }

    private func marker(in dir: URL) -> String? {
        (try? String(contentsOf: dir.appendingPathComponent(Self.markerName), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything in `dir` that belongs to an account (not shared downloads or Finder litter).
    private func accountItems(in dir: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { !Self.sharedItems.contains($0) && $0 != ".DS_Store" }
    }

    private func moveSharedItems(from source: URL, to destination: URL) {
        for name in Self.sharedItems {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) {
                try? move(from, to)
            }
        }
    }

    private func removeIfEmpty(_ dir: URL) throws {
        guard fm.fileExists(atPath: dir.path) else { return }
        let contents = try fm.contentsOfDirectory(atPath: dir.path).filter { $0 != ".DS_Store" }
        guard contents.isEmpty else { throw WyeError.unsavedLogin }
        try fm.removeItem(at: dir)
    }
}

/// Controls a real app through its bundle identifier.
public struct RunningAppControl: AppControl {
    let bundleID: String
    var timeout: TimeInterval = 30

    public init(bundleID: String) { self.bundleID = bundleID }

    private var instances: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }

    private var bundlePath: String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }

    /// True while the app or any of its helper processes is still alive.
    public func isRunning() -> Bool {
        if !instances.isEmpty { return true }
        guard let bundlePath, let ps = try? Shell.run("/bin/ps", ["-axo", "comm="]) else { return false }
        return Self.hasAppProcess(psOutput: ps.out, bundlePath: bundlePath)
    }

    /// Whether any process from inside the app bundle is alive. The browser bridge is
    /// started by Chrome, outlives the app, and does not use the app's data folder.
    static func hasAppProcess(psOutput: String, bundlePath: String) -> Bool {
        psOutput.split(separator: "\n").contains {
            $0.hasPrefix(bundlePath + "/") && !$0.hasSuffix("/chrome-native-host")
        }
    }

    public func quit() -> Bool {
        instances.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isRunning() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !isRunning()
    }

    public func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
