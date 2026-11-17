import AppKit
@preconcurrency import WyeCore
import ServiceManagement
import SwiftUI

@main
struct WyeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon).accessibilityLabel("Wye")
            } else {
                Image(systemName: "person.2.circle").accessibilityLabel("Wye")
            }
        }
    }

    /// The designer's single-colour mark, bundled by scripts/build-app.sh. Marked as a
    /// template so macOS recolours it for light and dark menu bars. Absent under `swift run`.
    private static let menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ForEach(model.rows) { row in
            Section(row.title) {
                ForEach(row.profiles, id: \.self) { profile in
                    Button {
                        model.switchTo(row, profile: profile)
                    } label: {
                        if profile == row.active {
                            Label(profile, systemImage: "checkmark")
                        } else {
                            Text(profile)
                        }
                    }
                    .disabled(model.busy || profile == row.active)
                }
                if row.profiles.isEmpty {
                    Text("No saved accounts yet")
                }
                Button("Save current login as…") { model.saveCurrent(row) }
                    .disabled(model.busy || !row.hasLogin)
                Button("Add another account…") { model.addAccount(row) }
                    .disabled(model.busy || row.active == nil)
            }
        }
        Divider()
        Toggle("Open at login", isOn: Binding(
            get: { model.opensAtLogin },
            set: { model.setOpensAtLogin($0) }))
        Button("Quit Wye") { NSApp.terminate(nil) }
    }
}

struct ProviderRow: Identifiable {
    let id: String
    let name: String
    let accountLabel: String?
    let profiles: [String]
    let active: String?
    let hasLogin: Bool

    var title: String {
        var parts = [name]
        if let accountLabel { parts.append(accountLabel) }
        if active == nil, hasLogin { parts.append("current login not saved") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var rows: [ProviderRow] = []
    @Published var busy = false
    @Published var opensAtLogin = SMAppService.mainApp.status == .enabled

    private let switcher = Switcher.live()
    private var timer: Timer?

    init() {
        refresh()
        // Logins can change outside Wye (signing in or out by hand), so re-read now and then.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !busy else { return }
        let state = switcher.state()
        rows = switcher.providers.map { provider in
            let entry = state.providers[provider.id]
            return ProviderRow(
                id: provider.id,
                name: provider.displayName,
                accountLabel: provider.currentAccountLabel(),
                profiles: entry?.profiles ?? [],
                active: entry?.active,
                hasLogin: provider.hasLiveLogin())
        }
    }

    func switchTo(_ row: ProviderRow, profile: String) {
        guard let provider = provider(row) else { return }
        if let warning = provider.runningWarning(),
            !confirm("Switch \(row.name) to \(profile)?", detail: warning, action: "Switch")
        {
            return
        }
        run { try $0.switchTo(row.id, profile: profile) }
    }

    func saveCurrent(_ row: ProviderRow) {
        let suggestion = row.active ?? ""
        guard let name = ask(
            "Save the current \(row.name) login as…",
            detail: "Give this account a short name, for example Personal or Company.",
            value: suggestion)
        else { return }
        run { try $0.saveCurrent(row.id, as: name) }
    }

    func addAccount(_ row: ProviderRow) {
        guard let provider = provider(row), let active = row.active else { return }
        var detail = "\(row.name) will be signed out. Your current login stays saved as \"\(active)\". "
            + "Sign in with the other account, then choose \"Save current login as…\"."
        if let warning = provider.runningWarning() { detail += "\n\n" + warning }
        guard confirm("Add another \(row.name) account?", detail: detail, action: "Sign Out") else { return }
        run { try $0.addAccount(row.id) }
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showError(error)
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Helpers

    private func provider(_ row: ProviderRow) -> AccountProvider? {
        switcher.providers.first { $0.id == row.id }
    }

    /// Runs a switch off the main thread: quitting Claude can take several seconds.
    private func run(_ work: @escaping (Switcher) throws -> Void) {
        busy = true
        let switcher = self.switcher
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: Error?
            do { try work(switcher) } catch { failure = error }
            DispatchQueue.main.async {
                self.busy = false
                self.refresh()
                if let failure { self.showError(failure) }
            }
        }
    }

    private func confirm(_ title: String, detail: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func ask(_ title: String, detail: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Wye could not finish"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
