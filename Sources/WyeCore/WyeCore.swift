import Foundation

public enum WyeError: LocalizedError, Equatable {
    case malformedJSON
    case keychain(String)
    case secretTooLong
    case invalidProfileName(String)
    case profileExists(String)
    case profileMissing(String)
    case noLiveLogin
    case unsavedLogin
    case accountMismatch(profile: String)
    case alreadySaved(as: String)
    case appWouldNotQuit
    case markerMismatch(String)
    case unknownProvider(String)

    public var errorDescription: String? {
        switch self {
        case .malformedJSON:
            return "A settings file is not valid JSON, so it was left untouched."
        case .keychain(let detail):
            return "Keychain error: \(detail)"
        case .secretTooLong:
            return "This login is too large to store safely through the Keychain command line tool. Nothing was changed."
        case .invalidProfileName(let name):
            return "\"\(name)\" is not a usable name. Use up to 40 letters, digits, spaces, - or _."
        case .profileExists(let name):
            return "An account named \"\(name)\" is already saved. Pick another name."
        case .profileMissing(let name):
            return "The saved login for \"\(name)\" could not be found."
        case .noLiveLogin:
            return "There is no login to save. Sign in first."
        case .unsavedLogin:
            return "The current login has not been saved yet. Use \"Save current login as…\" first so it is not lost."
        case .accountMismatch(let profile):
            return "The account currently signed in is not the one saved as \"\(profile)\". Save it under a new name first."
        case .alreadySaved(let name):
            return "The current login is already saved as \"\(name)\"."
        case .appWouldNotQuit:
            return "Claude did not quit in time, so nothing was switched. Close it and try again."
        case .markerMismatch(let detail):
            return "Profile folders do not match what Wye expects (\(detail)). Nothing was switched."
        case .unknownProvider(let id):
            return "Unknown app: \(id)"
        }
    }
}

/// One switchable tool (Claude CLI, Claude desktop, later Codex…).
public protocol AccountProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    /// Something human readable about the live account, e.g. its email.
    func currentAccountLabel() -> String?
    /// Text to show before switching, when switching now has a side effect.
    func runningWarning() -> String?
    func hasLiveLogin() -> Bool
    /// Record the live login under `profile`. The live login stays in place.
    func capture(as profile: String) throws
    /// Make `target` live. `current` names the profile that is live now, if it was saved.
    func activate(_ target: String, replacing current: String?) throws
    /// Put the live login away under `current` and leave the tool signed out.
    func deactivate(current: String) throws
}

enum AtomicFile {
    /// Writes via a temporary file and rename, so readers never see a half-written file.
    static func write(_ data: Data, to url: URL, permissions: Int? = nil) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).wye-\(UUID().uuidString)")
        try data.write(to: tmp)
        do {
            if let permissions {
                try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: tmp.path)
            }
            guard rename(tmp.path, url.path) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}

enum Shell {
    struct Result {
        let status: Int32
        let out: String
        let err: String
    }

    static func run(_ executable: String, _ arguments: [String], stdin: String? = nil) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try? input.fileHandleForWriting.close()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errData, as: UTF8.self))
    }
}
