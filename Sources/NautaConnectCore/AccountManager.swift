import Foundation

public enum AccountError: Error {
    case missingCredentials
    case duplicate
    case keychainFailure
    case busy
    case logoutFailed(Error)
}

public final class AccountManager {
    private let store: SessionStore
    private let savePassword: (String, String) -> Bool

    public init(store: SessionStore, savePassword: @escaping (String, String) -> Bool = {
        KeychainHelper.savePassword($0, account: $1)
    }) {
        self.store = store
        self.savePassword = savePassword
    }

    public func add(username: String, password: String) throws {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { throw AccountError.missingCredentials }
        guard !store.accounts.contains(where: { $0.caseInsensitiveCompare(username) == .orderedSame }) else {
            throw AccountError.duplicate
        }
        guard savePassword(password, username) else { throw AccountError.keychainFailure }
        store.appendAccount(username)
    }
}

@MainActor
public final class AccountConnector {
    public private(set) var isBusy = false
    private let store: SessionStore
    private let login: (String, String) async throws -> PortalSession
    private let logout: (PortalSession) async throws -> Void

    public init(store: SessionStore,
                login: @escaping (String, String) async throws -> PortalSession,
                logout: @escaping (PortalSession) async throws -> Void) {
        self.store = store
        self.login = login
        self.logout = logout
    }

    public func connect(username: String, password: String) async throws {
        guard !isBusy else { throw AccountError.busy }
        if store.session?.username == username { return }
        isBusy = true
        defer { isBusy = false }
        if let session = store.session {
            do {
                try await logout(session)
            } catch {
                throw AccountError.logoutFailed(error)
            }
            store.session = nil
        }
        store.username = username
        store.session = try await login(username, password)
    }
}
