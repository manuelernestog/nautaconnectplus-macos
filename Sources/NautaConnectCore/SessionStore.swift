import Foundation

/// Persists everything except the password (that lives in the Keychain).
/// Keeping the session on disk is what makes logout survive app restarts.
public final class SessionStore {
    public static let shared = SessionStore()

    private let defaults: UserDefaults
    private enum Keys {
        static let session = "portalSession"
        static let username = "username"
        static let accounts = "accounts"
        static let language = "language"
        static let showTimeInMenuBar = "showTimeInMenuBar"
        static let autoReconnect = "autoReconnect"
        static let autoReconnectIntervalSeconds = "autoReconnectIntervalSeconds"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Session

    public var session: PortalSession? {
        get {
            guard let data = defaults.data(forKey: Keys.session) else { return nil }
            return try? JSONDecoder().decode(PortalSession.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.session)
            } else {
                defaults.removeObject(forKey: Keys.session)
            }
        }
    }

    // MARK: - Preferences

    public var username: String {
        get { defaults.string(forKey: Keys.username) ?? "" }
        set { defaults.set(newValue, forKey: Keys.username) }
    }

    public var accounts: [String] {
        defaults.stringArray(forKey: Keys.accounts) ?? (username.isEmpty ? [] : [username])
    }

    func appendAccount(_ username: String) {
        defaults.set(accounts + [username], forKey: Keys.accounts)
        if self.username.isEmpty { self.username = username }
    }

    func removeAccount(_ username: String) {
        let remaining = accounts.filter { $0 != username }
        defaults.set(remaining, forKey: Keys.accounts)
        if self.username == username { self.username = remaining.first ?? "" }
    }

    public var language: Language {
        get {
            guard let raw = defaults.string(forKey: Keys.language),
                  let lang = Language(rawValue: raw) else { return Language.system }
            return lang
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.language) }
    }

    public var showTimeInMenuBar: Bool {
        get { defaults.object(forKey: Keys.showTimeInMenuBar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showTimeInMenuBar) }
    }

    public var autoReconnect: Bool {
        get { defaults.object(forKey: Keys.autoReconnect) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.autoReconnect) }
    }

    public var autoReconnectIntervalSeconds: Int {
        get {
            let stored = defaults.integer(forKey: Keys.autoReconnectIntervalSeconds)
            return ReconnectPolicy.supportedIntervals.contains(stored) ? stored : ReconnectPolicy.defaultIntervalSeconds
        }
        set {
            let valid = ReconnectPolicy.supportedIntervals.contains(newValue)
                ? newValue
                : ReconnectPolicy.defaultIntervalSeconds
            defaults.set(valid, forKey: Keys.autoReconnectIntervalSeconds)
        }
    }
}
