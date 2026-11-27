import AppKit
import NautaConnectCore
import ServiceManagement

/// Account management and application preferences.
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onSave: (() -> Void)?
    var isAccountInUse: (String) -> Bool = { SessionStore.shared.session?.username == $0 }

    private let accountTable = NSTableView()
    private var accountEditor: AddAccountWindowController?
    private let languagePopup = NSPopUpButton()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let showTimeInMenuBarCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoReconnectCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let intervalLabel = NSTextField(labelWithString: "")
    private let intervalPopup = NSPopUpButton()
    private let store = SessionStore.shared

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        loadValues()
    }

    private func buildUI() {
        guard let window else { return }
        window.title = L10n.t(.settingsTitle)

        let languageLabel = label(L10n.t(.languageLabel))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("username"))
        column.resizingMask = .autoresizingMask
        accountTable.addTableColumn(column)
        accountTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        accountTable.autoresizingMask = [.width]
        accountTable.headerView = nil
        accountTable.dataSource = self
        accountTable.delegate = self
        accountTable.rowHeight = 32
        let scroll = NSScrollView()
        scroll.documentView = accountTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let add = NSButton(title: L10n.t(.addAccount), target: self, action: #selector(presentAddAccount))
        languagePopup.addItems(withTitles: Language.allCases.map(\.displayName))

        launchAtLoginCheckbox.title = L10n.t(.launchAtLogin)
        // SMAppService needs macOS 13+; hide the option on older systems.
        if #unavailable(macOS 13.0) {
            launchAtLoginCheckbox.isHidden = true
        }

        showTimeInMenuBarCheckbox.title = L10n.t(.showTimeInMenuBar)

        autoReconnectCheckbox.title = L10n.t(.autoReconnect)
        autoReconnectCheckbox.target = self
        autoReconnectCheckbox.action = #selector(autoReconnectToggled)

        intervalLabel.stringValue = L10n.t(.autoReconnectInterval)
        intervalLabel.alignment = .right
        intervalPopup.addItems(withTitles: ReconnectPolicy.supportedIntervals.map(formatIntervalTitle))

        let saveButton = NSButton(title: L10n.t(.save), target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let grid = NSGridView(views: [
            [label(L10n.t(.accounts)), add],
            [NSGridCell.emptyContentView, scroll],
            [languageLabel, languagePopup],
            [NSGridCell.emptyContentView, launchAtLoginCheckbox],
            [NSGridCell.emptyContentView, showTimeInMenuBarCheckbox],
            [NSGridCell.emptyContentView, autoReconnectCheckbox],
            [intervalLabel, intervalPopup],
            [NSGridCell.emptyContentView, saveButton],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.row(at: 0).yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = window.contentView!
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            scroll.heightAnchor.constraint(equalToConstant: 110),
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func loadValues() {
        accountTable.reloadData()
        languagePopup.selectItem(at: Language.allCases.firstIndex(of: store.language) ?? 0)
        if #available(macOS 13.0, *) {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        showTimeInMenuBarCheckbox.state = store.showTimeInMenuBar ? .on : .off
        autoReconnectCheckbox.state = store.autoReconnect ? .on : .off
        let intervalIndex = ReconnectPolicy.supportedIntervals.firstIndex(of: store.autoReconnectIntervalSeconds) ?? 1
        intervalPopup.selectItem(at: intervalIndex)
        updateIntervalControlState()
    }

    @objc private func autoReconnectToggled() {
        updateIntervalControlState()
    }

    private func updateIntervalControlState() {
        let enabled = autoReconnectCheckbox.state == .on
        intervalPopup.isEnabled = enabled
        intervalLabel.textColor = enabled ? .labelColor : .secondaryLabelColor
    }

    private func formatIntervalTitle(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) \(L10n.t(.secondsShort))"
        }
        return "\(seconds / 60) \(L10n.t(.minutesUnit))"
    }

    @objc private func save() {
        let language = Language.allCases[languagePopup.indexOfSelectedItem]
        store.language = language
        L10n.language = language
        store.showTimeInMenuBar = showTimeInMenuBarCheckbox.state == .on
        store.autoReconnect = autoReconnectCheckbox.state == .on
        let selectedIntervalIndex = intervalPopup.indexOfSelectedItem
        if ReconnectPolicy.supportedIntervals.indices.contains(selectedIntervalIndex) {
            store.autoReconnectIntervalSeconds = ReconnectPolicy.supportedIntervals[selectedIntervalIndex]
        }

        if #available(macOS 13.0, *) {
            // Best effort: registration fails outside a proper .app bundle (e.g. swift run).
            do {
                if launchAtLoginCheckbox.state == .on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Launch at login toggle failed: \(error.localizedDescription)")
            }
        }

        onSave?()

        // Language may have changed; rebuild the window next time it opens.
        close()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.accounts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let username = store.accounts[row]
        return AccountRowView(username: username) { [weak self] in self?.deleteAccount(username: username) }
    }

    private func deleteAccount(username: String) {
        guard let window, window.attachedSheet == nil else { return }
        guard !isAccountInUse(username) else {
            showAccountError(title: .accountInUseTitle, message: .accountInUseMessage)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t(.deleteAccount)
        alert.informativeText = String(format: L10n.t(.deleteAccountConfirmation), username)
        alert.addButton(withTitle: L10n.t(.deleteAccount))
        alert.addButton(withTitle: L10n.t(.cancel))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do {
                try AccountManager(store: self.store).remove(username: username, isInUse: self.isAccountInUse(username))
                self.accountTable.reloadData()
                self.onSave?()
            } catch AccountError.accountInUse {
                self.showAccountError(title: .accountInUseTitle, message: .accountInUseMessage)
            } catch {
                self.showAccountError(title: .errorTitle, message: .deleteAccountFailed)
            }
        }
    }

    private func showAccountError(title: L10n.Key, message: L10n.Key) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t(title)
        alert.informativeText = L10n.t(message)
        alert.addButton(withTitle: L10n.t(.ok))
        alert.beginSheetModal(for: window)
    }

    @objc func presentAddAccount() {
        guard let window, window.attachedSheet == nil else { return }
        let editor = AddAccountWindowController()
        editor.onAdd = { [weak self] in
            self?.accountTable.reloadData()
            self?.onSave?()
        }
        accountEditor = editor
        guard let sheet = editor.window else { return }
        window.beginSheet(sheet) { [weak self] _ in self?.accountEditor = nil }
    }
}
