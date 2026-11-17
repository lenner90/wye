import Foundation
import XCTest
@testable import WyeCore

final class FakeSecretStore: SecretStore {
    var items: [String: String] = [:]
    var failWritesTo: String?

    func read(service: String, account: String) throws -> String? {
        items["\(service)|\(account)"]
    }

    func write(service: String, account: String, value: String) throws {
        if service == failWritesTo { throw WyeError.keychain("write refused") }
        items["\(service)|\(account)"] = value
    }

    func delete(service: String, account: String) throws {
        items["\(service)|\(account)"] = nil
    }
}

final class FakeAppControl: AppControl {
    var running = true
    var quitSucceeds = true
    var events: [String] = []

    func isRunning() -> Bool { running }

    func quit() -> Bool {
        events.append("quit")
        if quitSucceeds { running = false }
        return quitSucceeds
    }

    func launch() {
        events.append("launch")
        running = true
    }
}

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wye-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) {
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: url, atomically: true, encoding: .utf8)
}

func read(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}
