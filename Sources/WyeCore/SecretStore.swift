import Foundation

public protocol SecretStore {
    func read(service: String, account: String) throws -> String?
    func write(service: String, account: String, value: String) throws
    func delete(service: String, account: String) throws
}

/// Keychain access through `/usr/bin/security`, the same tool the Claude CLI uses,
/// so its items can be read and updated without a permission prompt.
/// Secrets are passed on stdin, never as command arguments.
public struct SecurityCLIKeychain: SecretStore {
    private static let tool = "/usr/bin/security"
    private static let notFound: Int32 = 44
    /// `security -i` silently truncates input lines longer than 4096 bytes.
    static let maxCommandLength = 4000

    public init() {}

    public func read(service: String, account: String) throws -> String? {
        let result = try Shell.run(
            Self.tool, ["find-generic-password", "-s", service, "-a", account, "-w"])
        if result.status == Self.notFound { return nil }
        guard result.status == 0 else {
            throw WyeError.keychain("could not read \"\(service)\" (code \(result.status))")
        }
        var value = result.out
        if value.hasSuffix("\n") { value.removeLast() }
        return value
    }

    public func write(service: String, account: String, value: String) throws {
        try Self.checkQuotable(service)
        try Self.checkQuotable(account)
        let hex = value.utf8.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        guard command.utf8.count <= Self.maxCommandLength else { throw WyeError.secretTooLong }
        let result = try Shell.run(Self.tool, ["-i"], stdin: command)
        guard result.status == 0, try read(service: service, account: account) == value else {
            throw WyeError.keychain("could not write \"\(service)\"")
        }
    }

    public func delete(service: String, account: String) throws {
        let result = try Shell.run(
            Self.tool, ["delete-generic-password", "-s", service, "-a", account])
        guard result.status == 0 || result.status == Self.notFound else {
            throw WyeError.keychain("could not delete \"\(service)\" (code \(result.status))")
        }
    }

    private static func checkQuotable(_ text: String) throws {
        if text.contains(where: { $0 == "\"" || $0 == "\\" || $0.isNewline }) {
            throw WyeError.keychain("unsupported character in name")
        }
    }
}
