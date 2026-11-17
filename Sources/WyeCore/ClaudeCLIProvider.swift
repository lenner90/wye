import Foundation

/// Switches the account of the `claude` command line tool.
/// Its login is a Keychain item plus the `oauthAccount` block of `~/.claude.json`.
public final class ClaudeCLIProvider: AccountProvider {
    public let id = "claude-cli"
    public let displayName = "Claude CLI"

    static let liveService = "Claude Code-credentials"
    static let accountKey = "oauthAccount"
    private static let backupsToKeep = 10
    private static var backupCounter = 0

    private let configURL: URL
    private let secrets: SecretStore
    private let account: String
    private let supportDir: URL
    private let runningSessions: () -> Int
    private let fm = FileManager.default

    public init(
        configURL: URL, secrets: SecretStore, account: String, supportDir: URL,
        runningSessions: @escaping () -> Int
    ) {
        self.configURL = configURL
        self.secrets = secrets
        self.account = account
        self.supportDir = supportDir
        self.runningSessions = runningSessions
    }

    /// The provider wired to the real files and Keychain of this Mac.
    public static func live(supportDir: URL) -> ClaudeCLIProvider {
        ClaudeCLIProvider(
            configURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"),
            secrets: SecurityCLIKeychain(),
            account: NSUserName(),
            supportDir: supportDir,
            runningSessions: {
                let ps = try? Shell.run("/bin/ps", ["-axo", "comm="])
                return countCLISessions(psOutput: ps?.out ?? "")
            })
    }

    /// Counts `claude` processes started from a terminal. Sessions run by the desktop
    /// app use the desktop login and are not affected by a CLI switch.
    static func countCLISessions(psOutput: String) -> Int {
        psOutput.split(separator: "\n").filter { line in
            let path = line.trimmingCharacters(in: .whitespaces)
            return (path as NSString).lastPathComponent == "claude"
                && !path.contains("/Application Support/Claude/")
        }.count
    }

    // MARK: AccountProvider

    public func currentAccountLabel() -> String? {
        guard let block = liveAccountBlock() else { return nil }
        return Self.field("emailAddress", in: block)
    }

    public func runningWarning() -> String? {
        let count = runningSessions()
        guard count > 0 else { return nil }
        return "\(count) Claude CLI session\(count == 1 ? " is" : "s are") running. "
            + "Close them first: a running session can write the old account's login back."
    }

    public func hasLiveLogin() -> Bool {
        ((try? secrets.read(service: Self.liveService, account: account)) ?? nil) != nil
    }

    public func capture(as profile: String) throws {
        guard let token = try secrets.read(service: Self.liveService, account: account) else {
            throw WyeError.noLiveLogin
        }
        let block = liveAccountBlock()
        if let saved = try? Data(contentsOf: blockURL(profile)),
            let savedID = Self.field("accountUuid", in: saved),
            let liveID = block.flatMap({ Self.field("accountUuid", in: $0) }),
            savedID != liveID
        {
            throw WyeError.accountMismatch(profile: profile)
        }
        try secrets.write(service: profileService(profile), account: account, value: token)
        if let block {
            try AtomicFile.write(block, to: blockURL(profile), permissions: 0o600)
        } else {
            try? fm.removeItem(at: blockURL(profile))
        }
    }

    public func activate(_ target: String, replacing current: String?) throws {
        guard let token = try secrets.read(service: profileService(target), account: account) else {
            throw WyeError.profileMissing(target)
        }
        if hasLiveLogin() {
            guard let current else { throw WyeError.unsavedLogin }
            try capture(as: current)
        }
        try secrets.write(service: Self.liveService, account: account, value: token)
        let block = try? Data(contentsOf: blockURL(target))
        try updateConfig { data in
            if let block {
                return try TopLevelJSON.setting(key: Self.accountKey, rawValue: block, in: data)
            }
            return try TopLevelJSON.removing(key: Self.accountKey, from: data)
        }
    }

    public func deactivate(current: String) throws {
        if hasLiveLogin() { try capture(as: current) }
        try secrets.delete(service: Self.liveService, account: account)
        try updateConfig { try TopLevelJSON.removing(key: Self.accountKey, from: $0) }
    }

    // MARK: Internals

    private func profileService(_ profile: String) -> String { "Wye.claude-cli.\(profile)" }

    private func blockURL(_ profile: String) -> URL {
        supportDir.appendingPathComponent("cli/\(profile).json")
    }

    private func liveAccountBlock() -> Data? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return (try? TopLevelJSON.value(forKey: Self.accountKey, in: data)) ?? nil
    }

    private static func field(_ name: String, in block: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: block)) as? [String: Any])?[name] as? String
    }

    private func updateConfig(_ transform: (Data) throws -> Data) throws {
        let original = try? Data(contentsOf: configURL)
        let updated = try transform(original ?? Data("{}".utf8))
        guard updated != original else { return }
        var permissions = 0o600
        if let original {
            try backUp(original)
            let attributes = try fm.attributesOfItem(atPath: configURL.path)
            permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        }
        try AtomicFile.write(updated, to: configURL, permissions: permissions)
    }

    private func backUp(_ data: Data) throws {
        let dir = supportDir.appendingPathComponent("backups")
        Self.backupCounter += 1
        let stamp = String(
            format: "%017lld-%06d", Int64(Date().timeIntervalSince1970 * 1_000_000), Self.backupCounter)
        try AtomicFile.write(
            data, to: dir.appendingPathComponent("claude.json.\(stamp)"), permissions: 0o600)
        let all = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("claude.json.") }.sorted()
        for old in all.dropLast(Self.backupsToKeep) {
            try? fm.removeItem(at: dir.appendingPathComponent(old))
        }
    }
}
