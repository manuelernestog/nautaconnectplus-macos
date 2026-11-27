import AppKit
import NautaConnectCore
import UserNotifications

/// Owns the NSStatusItem: icon, elapsed-time title, and the dropdown menu
/// with connect/disconnect actions.
final class StatusItemController: NSObject, NSMenuDelegate {
    private enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case reconnecting(attempt: Int)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = PortalClient()
    private let store = SessionStore.shared
    @MainActor private lazy var accountConnector = AccountConnector(
        store: store,
        login: { [client] in try await client.login(username: $0, password: $1) },
        logout: { [client] in try await client.logout($0) }
    )
    private var settingsController: SettingsWindowController?
    private var accountOperations: [UUID: String] = [:]

    private var state: State = .disconnected
    private var timeLeft: String?
    private var timer: Timer?
    private var healthCheckTimer: Timer?
    private var disconnectDeadline: Date?
    private weak var timerMenuItem: NSMenuItem?

    // True only when a session was started manually in this run or confirmed live at launch.
    private var shouldMaintainConnection = false
    private var isCheckingSession = false
    private var reconnectTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var lastFatalReconnectError: String?

    override init() {
        super.init()

        statusItem.button?.image = MenuBarIcon.image()
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }

        // Restore a session persisted by a previous run, then verify it is still live.
        // Never auto-reconnect on launch if the server session already expired while the app was closed.
        if let session = store.session {
            store.username = session.username
            state = .connected
            startElapsedTimer()
            validateRestoredSession()
        }
        updateButton()
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        healthCheckTimer?.invalidate()
        reconnectTask?.cancel()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(statusLine()))
        if state == .disconnected, let err = lastFatalReconnectError {
            menu.addItem(disabledItem("\(L10n.t(.reconnectFailedTitle)): \(err)"))
        }
        if state == .connected {
            menu.addItem(disabledItem("\(L10n.t(.timeLeft)): \(timeLeft ?? "—")"))
            menu.addItem(makeItem(L10n.t(.refreshTimeLeft), action: #selector(refreshTimeLeftAction)))
        }
        menu.addItem(.separator())

        switch state {
        case .disconnected:
            menu.addItem(connectMenuItem())
        case .connected:
            if store.accounts.count > 1 { menu.addItem(connectMenuItem()) }
            menu.addItem(makeItem(L10n.t(.disconnect), action: #selector(disconnectAction), key: "d"))
            let timerItem = makeDisconnectTimerItem()
            timerMenuItem = timerItem
            menu.addItem(timerItem)
        case .reconnecting:
            menu.addItem(makeItem(L10n.t(.cancelReconnect), action: #selector(cancelReconnectAction)))
        case .connecting, .disconnecting:
            menu.addItem(disabledItem(L10n.t(.statusWorking)))
        }

        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.t(.settings), action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.t(.quit), action: #selector(quit), key: "q"))
    }

    private func connectMenuItem() -> NSMenuItem {
        let item = makeItem(L10n.t(.connect), action: #selector(connectAction), key: "c")
        guard store.accounts.count > 1 else { return item }
        item.action = nil
        item.keyEquivalent = ""
        let submenu = NSMenu()
        for username in store.accounts {
            let account = makeItem(username, action: #selector(selectAccount(_:)))
            account.representedObject = username
            account.state = store.session?.username == username ? .on : .off
            submenu.addItem(account)
        }
        submenu.addItem(.separator())
        submenu.addItem(makeItem(L10n.t(.addAccount), action: #selector(addAccountAction)))
        item.submenu = submenu
        return item
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let username = sender.representedObject as? String,
              store.accounts.contains(username) else { return }
        connect(username: username)
    }

    @objc private func addAccountAction() {
        openSettings()
        settingsController?.presentAddAccount()
    }

    private func statusLine() -> String {
        switch state {
        case .connected:
            return "\(L10n.t(.statusConnected)) — \(formattedElapsed())"
        case .disconnected:
            return L10n.t(.statusDisconnected)
        case .connecting, .disconnecting:
            return L10n.t(.statusWorking)
        case .reconnecting(let attempt):
            return "\(L10n.t(.statusReconnecting)) (\(attempt))"
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
        if store.accounts.isEmpty {
            addAccountAction()
        } else {
            connect(username: store.username)
        }
    }

    private func connect(username: String) {
        guard state == .disconnected || state == .connected else { return }
        if store.session?.username == username { return }
        guard !username.isEmpty,
              let password = KeychainHelper.loadPassword(account: username), !password.isEmpty else {
            showError(L10n.t(.missingCredentials))
            openSettings()
            return
        }

        let operationID = UUID()
        accountOperations[operationID] = username
        let wasMaintaining = shouldMaintainConnection
        shouldMaintainConnection = false
        stopHealthCheckTimer()
        stopElapsedTimer()
        lastFatalReconnectError = nil
        state = store.session == nil ? .connecting : .disconnecting
        updateButton()
        Task { @MainActor in
            defer { accountOperations.removeValue(forKey: operationID) }
            do {
                try await accountConnector.connect(username: username, password: password)
                disconnectDeadline = nil
                timerMenuItem = nil
                timeLeft = nil
                state = .connected
                shouldMaintainConnection = true
                startElapsedTimer()
                scheduleHealthCheckTimer()
                refreshTimeLeft()
            } catch AccountError.logoutFailed(let error) {
                state = .connected
                shouldMaintainConnection = wasMaintaining
                startElapsedTimer()
                scheduleHealthCheckTimer()
                showLogoutFailure(error.localizedDescription)
            } catch {
                shouldMaintainConnection = false
                clearSession()
                showError(error.localizedDescription)
            }
            updateButton()
        }
    }

    @objc private func disconnectAction() {
        guard state == .connected else { return }
        shouldMaintainConnection = false
        cancelPendingReconnect()
        stopHealthCheckTimer()

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
                shouldMaintainConnection = true
                scheduleHealthCheckTimer()
                showLogoutFailure(error.localizedDescription)
            }
            updateButton()
        }
    }

    @objc private func cancelReconnectAction() {
        shouldMaintainConnection = false
        cancelPendingReconnect()
        clearSession()
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
        if settingsController == nil || settingsController?.window?.isVisible != true {
            let controller = SettingsWindowController()
            controller.isAccountInUse = { [weak self] username in
                guard let self else { return true }
                return self.store.session?.username == username
                    || self.accountOperations.values.contains(username)
                    || (self.state != .disconnected && self.store.username == username)
            }
            controller.onSave = { [weak self] in
                self?.handleSettingsSaved()
            }
            settingsController = controller
        }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleSettingsSaved() {
        updateButton()
        switch state {
        case .connected:
            if store.autoReconnect && shouldMaintainConnection {
                scheduleHealthCheckTimer()
            } else {
                stopHealthCheckTimer()
            }
        case .reconnecting:
            if !store.autoReconnect {
                cancelReconnectAction()
            }
        case .disconnected, .connecting, .disconnecting:
            break
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Time left & Auto-reconnect

    private func validateRestoredSession() {
        guard let session = store.session else { return }
        Task { @MainActor in
            let result = await client.validateSession(session)
            guard state == .connected, store.session == session else { return }
            switch result {
            case .active(let time):
                timeLeft = time
                if state == .connected && store.session == session {
                    shouldMaintainConnection = true
                    scheduleHealthCheckTimer()
                }
            case .expired:
                // Session expired while the app was closed: clean up without auto-reconnecting.
                shouldMaintainConnection = false
                clearSession()
            case .unreachable:
                shouldMaintainConnection = false
            }
        }
    }

    private func refreshTimeLeft() {
        guard let session = store.session else { return }
        Task { @MainActor in
            let result = await client.validateSession(session)
            guard state == .connected, store.session == session else { return }
            switch result {
            case .active(let time):
                timeLeft = time
            case .expired:
                if shouldMaintainConnection && store.autoReconnect && state == .connected {
                    beginAutoReconnect()
                } else {
                    clearSession()
                }
            case .unreachable:
                break
            }
        }
    }

    private func scheduleHealthCheckTimer() {
        stopHealthCheckTimer()
        guard state == .connected, shouldMaintainConnection, store.autoReconnect else { return }
        let interval = TimeInterval(store.autoReconnectIntervalSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
        timer.tolerance = min(10, interval * 0.15)
        RunLoop.main.add(timer, forMode: .common)
        healthCheckTimer = timer
    }

    private func stopHealthCheckTimer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    private func performHealthCheck() {
        guard state == .connected,
              shouldMaintainConnection,
              store.autoReconnect,
              !isCheckingSession,
              let session = store.session else { return }

        isCheckingSession = true
        Task { @MainActor in
            defer { isCheckingSession = false }
            let validation = await client.validateSession(session)
            guard state == .connected,
                  shouldMaintainConnection,
                  store.autoReconnect,
                  store.session == session else { return }

            switch validation {
            case .active(let time):
                timeLeft = time
            case .unreachable:
                break
            case .expired:
                beginAutoReconnect()
            }
        }
    }

    private func beginAutoReconnect() {
        guard shouldMaintainConnection, store.autoReconnect else { return }
        if let deadline = disconnectDeadline, Date() >= deadline {
            shouldMaintainConnection = false
            clearSession()
            return
        }

        cancelPendingReconnect()
        stopHealthCheckTimer()
        stopElapsedTimer()
        store.session = nil
        timeLeft = nil
        state = .reconnecting(attempt: 1)
        updateButton()

        let operationID = UUID()
        accountOperations[operationID] = store.username
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.accountOperations.removeValue(forKey: operationID) }
            await self.runReconnectLoop()
        }
    }

    @MainActor
    private func runReconnectLoop() async {
        var attempt = 1
        while !Task.isCancelled && shouldMaintainConnection && store.autoReconnect {
            if let deadline = disconnectDeadline, Date() >= deadline {
                shouldMaintainConnection = false
                clearSession()
                return
            }

            state = .reconnecting(attempt: attempt)
            updateButton()

            let username = store.username
            guard !username.isEmpty,
                  let password = KeychainHelper.loadPassword(account: username), !password.isEmpty else {
                shouldMaintainConnection = false
                let message = L10n.t(.missingCredentials)
                lastFatalReconnectError = message
                clearSession()
                notifyFatalReconnectFailure(message)
                return
            }

            do {
                let newSession = try await client.login(username: username, password: password)
                if Task.isCancelled || !shouldMaintainConnection {
                    // User cancelled while login was in flight; log back out so paid time does not leak.
                    try? await client.logout(newSession)
                    return
                }
                store.session = newSession
                state = .connected
                lastFatalReconnectError = nil
                reconnectTask = nil
                startElapsedTimer()
                scheduleHealthCheckTimer()
                refreshTimeLeft()
                updateButton()
                return
            } catch {
                if Task.isCancelled || !shouldMaintainConnection {
                    return
                }
                switch ReconnectPolicy.disposition(for: error, attempt: attempt) {
                case .stop(let reason):
                    shouldMaintainConnection = false
                    lastFatalReconnectError = reason
                    reconnectTask = nil
                    clearSession()
                    notifyFatalReconnectFailure(reason)
                    return
                case .retry(let delay):
                    attempt += 1
                    let sleepSeconds: TimeInterval
                    if let deadline = disconnectDeadline {
                        sleepSeconds = min(delay, max(0, deadline.timeIntervalSinceNow))
                    } else {
                        sleepSeconds = delay
                    }
                    if sleepSeconds > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                    }
                }
            }
        }
    }

    private func cancelPendingReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func handleSystemWake() {
        guard shouldMaintainConnection, store.autoReconnect else { return }
        if state == .connected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.performHealthCheck()
            }
        } else if case .reconnecting = state {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, case .reconnecting = self.state else { return }
                self.beginAutoReconnect()
            }
        }
    }

    private func clearSession() {
        store.session = nil
        state = .disconnected
        disconnectDeadline = nil
        timerMenuItem = nil
        stopElapsedTimer()
        stopHealthCheckTimer()
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
            } else if case .reconnecting = state {
                cancelReconnectAction()
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
            shouldMaintainConnection = false
            clearSession()
        }
    }

    private func notifyFatalReconnectFailure(_ reason: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            showError("\(L10n.t(.reconnectFailedTitle))\n\n\(reason)")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            let deliver = {
                let content = UNMutableNotificationContent()
                content.title = L10n.t(.reconnectFailedTitle)
                content.body = reason
                let request = UNNotificationRequest(
                    identifier: "com.nautaconnect.reconnect-stopped",
                    content: content,
                    trigger: nil
                )
                center.add(request)
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                deliver()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        deliver()
                    } else {
                        DispatchQueue.main.async {
                            self?.showError("\(L10n.t(.reconnectFailedTitle))\n\n\(reason)")
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    self?.showError("\(L10n.t(.reconnectFailedTitle))\n\n\(reason)")
                }
            }
        }
    }
}
