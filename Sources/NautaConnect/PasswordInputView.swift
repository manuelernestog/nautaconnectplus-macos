import AppKit
import NautaConnectCore

final class PasswordInputView: NSView, NSTextFieldDelegate {
    var onChange: (() -> Void)?
    private let secureField = NSSecureTextField()
    private let revealedField = NSTextField()
    private let toggleButton = NSButton()
    private var isRevealed = false

    var textField: NSTextField { isRevealed ? revealedField : secureField }

    var stringValue: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            (isRevealed ? secureField : revealedField).stringValue = ""
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

    init() {
        super.init(frame: .zero)
        revealedField.isHidden = true
        for field in [secureField, revealedField] {
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            field.nextKeyView = toggleButton
            addSubview(field)
        }
        toggleButton.target = self
        toggleButton.action = #selector(toggleVisibility)
        toggleButton.bezelStyle = .regularSquare
        toggleButton.isBordered = false
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleButton)
        NSLayoutConstraint.activate([
            secureField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -6),
            secureField.centerYAnchor.constraint(equalTo: centerYAnchor),
            revealedField.leadingAnchor.constraint(equalTo: secureField.leadingAnchor),
            revealedField.trailingAnchor.constraint(equalTo: secureField.trailingAnchor),
            revealedField.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            toggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 24),
            toggleButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        updateToggleButton()
    }

    required init?(coder: NSCoder) { nil }

    func controlTextDidChange(_ notification: Notification) { onChange?() }

    func clear() {
        if textField.currentEditor() != nil { window?.makeFirstResponder(nil) }
        secureField.stringValue = ""
        revealedField.stringValue = ""
        isRevealed = false
        secureField.isHidden = false
        revealedField.isHidden = true
        updateToggleButton()
    }

    @objc private func toggleVisibility() {
        let oldField = textField
        let value = oldField.stringValue
        let selection = (oldField.currentEditor() as? NSTextView)?.selectedRange()
        window?.makeFirstResponder(nil)
        isRevealed.toggle()
        oldField.isHidden = true
        oldField.stringValue = ""
        textField.stringValue = value
        textField.isHidden = false
        updateToggleButton()
        window?.makeFirstResponder(textField)
        if let selection, let editor = textField.currentEditor() as? NSTextView {
            let location = min(selection.location, value.utf16.count)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, value.utf16.count - location)))
        }
        onChange?()
    }

    private func updateToggleButton() {
        let title = L10n.t(isRevealed ? .hidePassword : .showPassword)
        toggleButton.image = NSImage(systemSymbolName: isRevealed ? "eye.slash" : "eye", accessibilityDescription: nil)
        toggleButton.toolTip = title
        toggleButton.setAccessibilityLabel(title)
    }
}
