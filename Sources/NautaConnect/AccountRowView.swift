import AppKit
import NautaConnectCore

final class AccountRowView: NSTableCellView {
    private let onDelete: () -> Void

    init(username: String, onDelete: @escaping () -> Void) {
        self.onDelete = onDelete
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: username)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil) ?? NSImage(),
                              target: self, action: #selector(deleteAccount))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = .systemRed
        button.toolTip = "\(L10n.t(.deleteAccount)): \(username)"
        button.setAccessibilityLabel(button.toolTip)
        label.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(button)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func deleteAccount() { onDelete() }
}
