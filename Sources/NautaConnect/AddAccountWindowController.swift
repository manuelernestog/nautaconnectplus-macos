import AppKit
import NautaConnectCore

final class AddAccountWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    var onAdd: (() -> Void)?
    private let usernameField = NSTextField()
    private let passwordField = PasswordInputView()
    private let saveButton = NSButton()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let formStack = NSStackView()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 210),
                              styleMask: [.titled], backing: .buffered, defer: false)
        self.init(window: window)
        window.delegate = self
        window.title = L10n.t(.addAccountTitle)
        window.isReleasedWhenClosed = false
        usernameField.placeholderString = L10n.t(.usernamePlaceholder)
        errorLabel.textColor = .systemRed
        usernameField.delegate = self
        passwordField.onChange = { [weak self] in self?.updateValidation() }
        let save = saveButton
        save.title = L10n.t(.save)
        save.target = self
        save.action = #selector(saveAccount)
        save.isEnabled = false
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: L10n.t(.cancel), target: self, action: #selector(cancelAdd))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView()
        buttons.distribution = .gravityAreas
        buttons.setViews([cancel, save], in: .trailing)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L10n.t(.usernameLabel)), usernameField],
            [NSTextField(labelWithString: L10n.t(.passwordLabel)), passwordField],
        ])
        grid.columnSpacing = 8
        grid.rowSpacing = 12
        grid.row(at: 1).yPlacement = .center
        let stack = formStack
        stack.orientation = .vertical
        stack.setViews([grid, errorLabel, buttons], in: .top)
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        usernameField.nextKeyView = passwordField.textField
        window.initialFirstResponder = usernameField
        resizeToFitContent()
    }

    @objc private func saveAccount() {
        updateValidation()
        guard saveButton.isEnabled else { return }
        do {
            try AccountManager(store: .shared).add(username: usernameField.stringValue, password: passwordField.stringValue)
            onAdd?()
            finish()
        } catch {
            switch error {
            case let failure as KeychainSaveError:
                errorLabel.stringValue = String(format: L10n.t(.keychainFailureDetails),
                                               String(failure.status), failure.localizedDescription)
            case AccountError.duplicate: errorLabel.stringValue = L10n.t(.duplicateAccount)
            case AccountError.keychainFailure: errorLabel.stringValue = L10n.t(.keychainFailure)
            default: errorLabel.stringValue = L10n.t(.missingCredentials)
            }
            resizeToFitContent()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        updateValidation()
    }

    private func updateValidation() {
        let accounts = SessionStore.shared.accounts
        saveButton.isEnabled = AccountFormValidation.canSave(
            username: usernameField.stringValue, password: passwordField.stringValue, existingAccounts: accounts
        )
        errorLabel.stringValue = AccountFormValidation.isDuplicate(username: usernameField.stringValue, existingAccounts: accounts)
            ? L10n.t(.duplicateAccount) : ""
        usernameField.nextKeyView = passwordField.textField
        resizeToFitContent()
    }

    private func resizeToFitContent() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: content.bounds.width, height: formStack.fittingSize.height + 40)
        if content.bounds.size != size { window.setContentSize(size) }
    }

    @objc private func cancelAdd() { finish() }

    func windowWillClose(_ notification: Notification) { passwordField.clear() }

    private func finish() {
        passwordField.clear()
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        close()
    }
}
