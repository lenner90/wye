<p align="center">
  <img src="design/logo/wye-app.png" width="128" alt="Wye app icon">
</p>

# Wye

Wye is a small macOS menu bar app that switches between accounts of the same AI tool with one click, for example a **personal** account and a **company** account, without signing out and back in each time.

It currently supports:

- **Claude Desktop**, the Claude app for Mac
- **Claude CLI**, the `claude` command line tool

More tools may be added later.

## Why

If you use one AI tool for both work and personal projects, changing accounts usually means signing out, signing in again, and sometimes going through a browser login, several times a day. Wye saves each account's login once. After that, switching is a single menu click.

## Install

**Requirements:** macOS 13 (Ventura) or later, on Apple Silicon or Intel.

There is no ready-made download. You build Wye yourself from the source code, which takes about a minute (see [Build from source](#build-from-source) below).

### From a disk image

To install Wye on another Mac, build `dist/Wye.dmg` with `./scripts/build-app.sh --dmg` and copy it over. Then:

1. Open `Wye.dmg` and drag **Wye** onto the **Applications** shortcut.
2. Open Wye from Applications.

Wye is not signed with an Apple Developer ID, so the first time you open it macOS may say it "cannot be opened because the developer cannot be verified". To open it anyway:

- Right-click (or Control-click) **Wye** in Applications, choose **Open**, then click **Open** again. Or:
- Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Wye message.

You only need to do this once.

### Build from source

You need Xcode or the Swift 5.9+ command line tools.

```bash
git clone https://github.com/lenner90/wye.git
cd wye
```

Build the app and install it into `/Applications` on this Mac:

```bash
./scripts/build-app.sh --install
```

Build a disk image to share with other Macs (creates `dist/Wye.dmg`):

```bash
./scripts/build-app.sh --dmg
```

With no options the script only builds `dist/Wye.app`. The app is built for both Apple Silicon and Intel.

## How to use

Wye has no Dock icon. Look for its icon in the menu bar at the top right of the screen. The menu has one section per tool.

**First account**

1. Sign in to Claude (desktop app or CLI) the normal way.
2. In the Wye menu, choose **Save current login as…** and give it a short name, such as `Personal`.

**Another account**

1. Choose **Add another account…**. Wye keeps your current login saved and signs the tool out.
2. Sign in with the other account the normal way.
3. Choose **Save current login as…** again and name it, such as `Company`.

**Switching**

Click an account name in the menu. A checkmark shows which account is active.

- **Claude Desktop:** if the app is open, Wye quits it, switches, and opens it again. Open chats and Code sessions in the app will be closed, and Wye asks you first.
- **Claude CLI:** if `claude` sessions are running in a terminal, Wye warns you before switching. Start new sessions afterwards to use the new account.

Turn on **Open at login** in the menu to start Wye automatically when you log in.

## Where your logins are stored

Everything stays on your Mac. Wye has no server and makes no network requests.

| What | Where |
|---|---|
| Claude CLI login tokens | macOS Keychain, through Apple's `/usr/bin/security` tool, the same way the Claude CLI stores them |
| Claude CLI account details | `~/Library/Application Support/Wye/cli/` |
| Backups of `~/.claude.json` (last 10, taken before each change) | `~/Library/Application Support/Wye/backups/` |
| Claude Desktop accounts | `~/Library/Application Support/Wye/desktop/`. Each account's whole Claude data folder is kept here and swapped in and out by renaming, never copied or deleted |

Wye refuses to switch if something looks wrong, for example a login that hasn't been saved yet or a folder it doesn't recognise. It shows an error and leaves your files as they are.

## Development

```bash
swift build        # build
swift test         # run the tests
swift run Wye      # run without bundling (uses a fallback menu bar icon)
```

Project layout:

```
Sources/WyeCore/   switching logic: one provider per tool, Keychain access, safe file writes
Sources/Wye/       the SwiftUI menu bar app
Tests/             unit tests for WyeCore
scripts/           build-app.sh: builds Wye.app and Wye.dmg
design/logo/       app and menu bar icons
docs/              design brief
```

To add support for another tool, implement the `AccountProvider` protocol in `Sources/WyeCore/WyeCore.swift` and register it in `Switcher`.

## Disclaimer

Wye is an independent project and is not affiliated with or endorsed by Anthropic. "Claude" is a trademark of its owner.
