<div align="center">

<img src="icon.svg" width="96" alt="NautaConnectPlus logo"/>

# NautaConnectPlus for macOS

**Connect, disconnect and track your Nauta session — right from the menu bar.**

> **Fork notice:** NautaConnectPlus is a fork of the original [NautaConnect for macOS](https://github.com/albertolicea00/nautaconnect-macos) by [@albertolicea00](https://github.com/albertolicea00).

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-000066)
![Swift](https://img.shields.io/badge/Swift-5.7-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)
![UI](https://img.shields.io/badge/UI-Espa%C3%B1ol%20%7C%20English-00CCFF)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

</div>

---

If you use the internet in Cuba, you know the ritual: open the ETECSA captive portal, log in, browse… and pray you never close that tab. Because if you do, there is no logout button anymore — and your precious hours keep burning.

**NautaConnectPlus fixes that.** It lives quietly in your menu bar and gives you the whole Nauta session lifecycle in one click:

- 🔌 **One-click connect & disconnect** — no browser, no tabs, no portal roulette.
- ⏱ **Live session timer in the menu bar** — always know how long you've been online.
- ⌛ **Remaining time at a glance** — queries your account's leftover hours directly from the portal.
- 🔐 **Your password stays in the macOS Keychain** — never in plain text, never logged, never sent anywhere but ETECSA.
- 🌐 **Español e inglés** — the app speaks both, switch anytime in Settings.
- 🪶 **Truly native, truly tiny** — pure Swift + AppKit. No Electron, no runtime, no 200 MB download. Your 2012 MacBook will not even notice it's running.

> Works with **Nauta Hogar** and **Nauta WiFi** accounts on any ETECSA network that authenticates through [secure.etecsa.net](https://secure.etecsa.net:8443/).

## Install

1. Grab the latest `NautaConnectPlus.app` from [Releases](../../releases) *(or build it yourself in two commands — see [SPECS.md](SPECS.md))*.
2. Drop it into `/Applications`.
3. Click the icon in your menu bar, open **Settings… → + Add account**, and save your `usuario@nauta.com.cu` credentials.

Building from source, the portal protocol, architecture and everything technical lives in **[SPECS.md](SPECS.md)**.

## Multiple accounts

Add accounts from **Settings… → + Add account**. Settings lists your saved usernames;
passwords stay in Keychain. Your existing account is kept automatically.
Use the trash icon beside an account to remove it and its saved password after
confirmation. An account in use cannot be deleted: disconnect it first.

**Save** is enabled only for an address ending in `@nauta.com.cu` or
`@nauta.co.cu` with a nonempty password. Already saved emails cannot be added again;
comparison ignores case and surrounding whitespace.

With one account, **Connect** remains a one-click action. With multiple accounts,
**Connect** opens a submenu listing them, followed by **+ Add account**, which opens
the add-account sheet in Settings. Selecting another account while connected logs
out the current account first, then connects the selected one. If logout fails,
the app does not connect the other account. Only one account is connected at a time.

## Original & sister projects

NautaConnectPlus is a fork of NautaConnect-macos builds on the original NautaConnect family of small native apps:

- **[nautaconnect-macos](https://github.com/albertolicea00/nautaconnect-macos)** — original macOS menu bar app (upstream)
- **[nautaconnect-windows](https://github.com/albertolicea00/nautaconnect-windows)** — native system-tray app for Windows
- **[nautaconnect-extension](https://github.com/albertolicea00/nautaconnect--extension)** — Chrome & Firefox extension

## Contributing

Bugs, ideas and PRs are very welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Disclaimer

NautaConnectPlus is an independent open-source project. It is **not** affiliated with, endorsed by, or supported by ETECSA. It simply automates the same requests your browser makes against the official portal. Use it with your own account, at your own risk.

## License

Licensed under the [MIT](LICENSE) License.
