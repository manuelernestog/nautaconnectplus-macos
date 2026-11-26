import AppKit
import NautaConnectCore

/// Owns the NSStatusItem: icon, elapsed-time title, and the dropdown menu
/// with connect/disconnect actions.
final class StatusItemController: NSObject, NSMenuDelegate {
    private enum State {
        case disconnected
        case connecting
        case connected
        case disconnecting
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = PortalClient()
    private let store = SessionStore.shared
    private var settingsController: SettingsWindowController?

    private var state: State = .disconnected
    private var timeLeft: String?
    private var timer: Timer?
    private var disconnectDeadline: Date?
    private weak var timerMenuItem: NSMenuItem?

    override init() {
        super.init()

        statusItem.button?.image = MenuBarIcon.image()
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Restore a session persisted by a previous run, then verify it is still live.
        if store.session != nil {
            state = .connected
            startElapsedTimer()
            refreshTimeLeft()
        }
        updateButton()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(statusLine()))
        if state == .connected {
            menu.addItem(disabledItem("\(L10n.t(.timeLeft)): \(timeLeft ?? "—")"))
            menu.addItem(makeItem(L10n.t(.refreshTimeLeft), action: #selector(refreshTimeLeftAction)))
        }
        menu.addItem(.separator())

        switch state {
        case .disconnected:
            menu.addItem(makeItem(L10n.t(.connect), action: #selector(connectAction), key: "c"))
        case .connected:
            menu.addItem(makeItem(L10n.t(.disconnect), action: #selector(disconnectAction), key: "d"))
            let timerItem = makeDisconnectTimerItem()
            timerMenuItem = timerItem
            menu.addItem(timerItem)
        case .connecting, .disconnecting:
            menu.addItem(disabledItem(L10n.t(.statusWorking)))
        }

        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.t(.settings), action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.t(.quit), action: #selector(quit), key: "q"))
    }

    private func statusLine() -> String {
        switch state {
        case .connected:
            return "\(L10n.t(.statusConnected)) — \(formattedElapsed())"
        case .disconnected:
            return L10n.t(.statusDisconnected)
        case .connecting, .disconnecting:
            return L10n.t(.statusWorking)
        }
    }

    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeDisconnectTimerItem() -> NSMenuItem {
        let title = disconnectTimerTitle()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if disconnectDeadline != nil {
            submenu.addItem(makeItem(L10n.t(.cancelTimer), action: #selector(cancelDisconnectTimerAction)))
            submenu.addItem(.separator())
        }

        for minutes in [5, 15, 30, 60, 120] {
            let preset = makeItem(presetTitle(minutes: minutes), action: #selector(selectDisconnectTimerPreset(_:)))
            preset.representedObject = minutes
            submenu.addItem(preset)
        }

        submenu.addItem(.separator())
        submenu.addItem(makeItem(L10n.t(.customTimer), action: #selector(customDisconnectTimerAction)))
        item.submenu = submenu
        return item
    }

    private func disconnectTimerTitle() -> String {
        if let formatted = formattedCountdown() {
            return "\(L10n.t(.disconnectIn)) \(formatted)"
        }
        return L10n.t(.disconnectTimer)
    }

    private func presetTitle(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) \(L10n.t(.minutesUnit))"
        }
        let hours = minutes / 60
        let unit = hours == 1 ? L10n.t(.hourUnit) : L10n.t(.hoursUnit)
        return "\(hours) \(unit)"
    }

    // MARK: - Actions

    @objc private func connectAction() {
        let username = store.username
        guard !username.isEmpty,
              let password = KeychainHelper.loadPassword(account: username), !password.isEmpty else {
            showError(L10n.t(.missingCredentials))
            openSettings()
            return
        }

        state = .connecting
        updateButton()
        Task { @MainActor in
            do {
                let session = try await client.login(username: username, password: password)
                store.session = session
                state = .connected
                startElapsedTimer()
                refreshTimeLeft()
            } catch {
                state = .disconnected
                showError(error.localizedDescription)
            }
            updateButton()
        }
    }

    @objc private func disconnectAction() {
        guard let session = store.session else {
            state = .disconnected
            updateButton()
            return
        }
        state = .disconnecting
        updateButton()
        Task { @MainActor in
            do {
                try await client.logout(session)
                clearSession()
            } catch {
                // Keep the session by default: dropping it would strand the user logged in.
                state = .connected
                showLogoutFailure(error.localizedDescription)
            }
            updateButton()
        }
    }

    @objc private func refreshTimeLeftAction() {
        refreshTimeLeft()
    }

    @objc private func selectDisconnectTimerPreset(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int, minutes > 0 else { return }
        startDisconnectTimer(minutes: minutes)
    }

    @objc private func customDisconnectTimerAction() {
        let alert = NSAlert()
        alert.messageText = L10n.t(.customTimerTitle)
        alert.informativeText = L10n.t(.customTimerPrompt)
        alert.addButton(withTitle: L10n.t(.startTimer))
        alert.addButton(withTitle: L10n.t(.cancel))

        let hoursField = NSTextField()
        hoursField.placeholderString = "0"
        hoursField.stringValue = "0"
        hoursField.alignment = .right

        let minutesField = NSTextField()
        minutesField.placeholderString = "30"
        minutesField.stringValue = "30"
        minutesField.alignment = .right

        let hoursLabel = NSTextField(labelWithString: L10n.t(.hoursUnit))
        let minutesLabel = NSTextField(labelWithString: L10n.t(.minutesUnit))

        let stack = NSStackView(views: [hoursField, hoursLabel, minutesField, minutesLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.setCustomSpacing(14, after: hoursLabel)
        NSLayoutConstraint.activate([
            hoursField.widthAnchor.constraint(equalToConstant: 56),
            minutesField.widthAnchor.constraint(equalToConstant: 56),
        ])
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)

        hoursField.nextKeyView = minutesField
        minutesField.nextKeyView = hoursField

        alert.accessoryView = stack
        alert.window.initialFirstResponder = hoursField

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let totalMinutes = parseCustomDurationMinutes(
            hoursText: hoursField.stringValue,
            minutesText: minutesField.stringValue
        ) else {
            showError(L10n.t(.customTimerInvalid))
            return
        }
        startDisconnectTimer(minutes: totalMinutes)
    }

    private func parseCustomDurationMinutes(hoursText: String, minutesText: String) -> Int? {
        guard let hours = parseNonNegativeInt(hoursText),
              let minutes = parseNonNegativeInt(minutesText) else {
            return nil
        }
        let (hourMinutes, overflow) = hours.multipliedReportingOverflow(by: 60)
        guard !overflow else { return nil }
        let (total, addOverflow) = hourMinutes.addingReportingOverflow(minutes)
        guard !addOverflow, total > 0 else { return nil }
        return total
    }

    private func parseNonNegativeInt(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        guard let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    @objc private func cancelDisconnectTimerAction() {
        disconnectDeadline = nil
        timerMenuItem?.title = L10n.t(.disconnectTimer)
    }

    private func startDisconnectTimer(minutes: Int) {
        guard state == .connected else { return }
        disconnectDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        timerMenuItem?.title = disconnectTimerTitle()
    }

    @objc private func openSettings() {
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.onSave = { [weak self] in
                self?.updateButton()
            }
            settingsController = controller
        }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Time left

    private func refreshTimeLeft() {
        guard let session = store.session else { return }
        Task { @MainActor in
            switch await client.validateSession(session) {
            case .active(let time):
                timeLeft = time
            case .expired:
                clearSession()
            case .unreachable:
                break
            }
        }
    }

    private func clearSession() {
        store.session = nil
        state = .disconnected
        disconnectDeadline = nil
        timerMenuItem = nil
        stopElapsedTimer()
        timeLeft = nil
        updateButton()
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
        // .common so the title keeps ticking while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerTick() {
        updateButton()
        guard let deadline = disconnectDeadline else { return }
        if Date() >= deadline {
            disconnectDeadline = nil
            if state == .connected {
                disconnectAction()
            }
        } else {
            timerMenuItem?.title = disconnectTimerTitle()
        }
    }

    private func stopElapsedTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formattedElapsed() -> String {
        guard let session = store.session else { return "0:00:00" }
        let total = Int(session.elapsed)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func formattedCountdown() -> String? {
        guard let deadline = disconnectDeadline else { return nil }
        let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        if remaining >= 3600 {
            return String(format: "%d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
        }
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func updateButton() {
        let shouldShowTime = state == .connected && store.showTimeInMenuBar
        statusItem.button?.title = shouldShowTime ? " " + formattedElapsed() : ""
        statusItem.button?.appearsDisabled = state != .connected
    }

    // MARK: - Errors

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t(.errorTitle)
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showLogoutFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t(.errorTitle)
        alert.informativeText = message
        alert.addButton(withTitle: L10n.t(.keepSession))
        alert.addButton(withTitle: L10n.t(.discardSession))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            clearSession()
        }
    }
}
