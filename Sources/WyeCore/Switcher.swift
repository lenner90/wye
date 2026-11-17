import Foundation

public struct ProviderState: Codable, Equatable {
    public var profiles: [String] = []
    /// The saved profile that is live right now; nil when the live login is unsaved or absent.
    public var active: String?
}

public struct WyeState: Codable, Equatable {
    public var providers: [String: ProviderState] = [:]
}

/// Remembers which accounts are saved for each tool and drives the providers.
/// The state file holds names only, never secrets.
public final class Switcher {
    public let providers: [AccountProvider]
    private let stateURL: URL

    public init(stateURL: URL, providers: [AccountProvider]) {
        self.stateURL = stateURL
        self.providers = providers
    }

    /// The switcher for this Mac, storing its data in Application Support/Wye.
    public static func live() -> Switcher {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wye")
        return Switcher(
            stateURL: support.appendingPathComponent("state.json"),
            providers: [
                ClaudeDesktopProvider.live(supportDir: support),
                ClaudeCLIProvider.live(supportDir: support),
            ])
    }

    public func state() -> WyeState {
        guard let data = try? Data(contentsOf: stateURL),
            let state = try? JSONDecoder().decode(WyeState.self, from: data)
        else { return WyeState() }
        return state
    }

    public func saveCurrent(_ providerID: String, as rawName: String) throws {
        let provider = try provider(providerID)
        let name = try Self.validName(rawName)
        var entry = state().providers[providerID] ?? ProviderState()
        if entry.profiles.contains(name), entry.active != name {
            throw WyeError.profileExists(name)
        }
        try provider.capture(as: name)
        if !entry.profiles.contains(name) { entry.profiles.append(name) }
        entry.active = name
        try save(entry, for: providerID)
    }

    public func switchTo(_ providerID: String, profile: String) throws {
        let provider = try provider(providerID)
        var entry = state().providers[providerID] ?? ProviderState()
        guard entry.profiles.contains(profile) else { throw WyeError.profileMissing(profile) }
        guard entry.active != profile else { return }
        try provider.activate(profile, replacing: entry.active)
        entry.active = profile
        try save(entry, for: providerID)
    }

    /// Puts the current login away and leaves the tool signed out, ready for another account.
    public func addAccount(_ providerID: String) throws {
        let provider = try provider(providerID)
        var entry = state().providers[providerID] ?? ProviderState()
        if let active = entry.active {
            try provider.deactivate(current: active)
        } else if provider.hasLiveLogin() {
            throw WyeError.unsavedLogin
        }
        entry.active = nil
        try save(entry, for: providerID)
    }

    private func provider(_ id: String) throws -> AccountProvider {
        guard let provider = providers.first(where: { $0.id == id }) else {
            throw WyeError.unknownProvider(id)
        }
        return provider
    }

    private func save(_ entry: ProviderState, for providerID: String) throws {
        var all = state()
        all.providers[providerID] = entry
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(all), to: stateURL, permissions: 0o600)
    }

    /// Names end up in folder and Keychain item names, so keep them plain.
    static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        guard !name.isEmpty, name.count <= 40,
            name.unicodeScalars.allSatisfy(allowed.contains)
        else { throw WyeError.invalidProfileName(raw) }
        return name
    }
}
