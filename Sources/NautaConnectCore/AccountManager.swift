import Foundation
import Security

public enum AccountError: Error {
    case missingCredentials
    case duplicate
    case keychainFailure
    case accountInUse
    case busy
    case logoutFailed(Error)
}

public final class AccountManager {
    private let store: SessionStore
    private let savePassword: (String, String) throws -> Void

    public init(store: SessionStore, savePassword: @escaping (String, String) -> Bool) {
        self.store = store
        self.savePassword = {
            guard savePassword($0, $1) else { throw AccountError.keychainFailure }
        }
    }

    public init(store: SessionStore, savePasswordStatus: @escaping (String, String) -> OSStatus = {
        KeychainHelper.savePasswordStatus($0, account: $1)
    }) {
        self.store = store
        self.savePassword = {
            let status = savePasswordStatus($0, $1)
            guard status == errSecSuccess else { throw KeychainSaveError(status: status) }
        }
    }

    public func add(username: String, password: String) throws {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { throw AccountError.missingCredentials }
        guard !AccountFormValidation.isDuplicate(username: username, existingAccounts: store.accounts) else {
            throw AccountError.duplicate
        }
        try savePassword(password, username)
        store.appendAccount(username)
    }

    public func remove(username: String, isInUse: Bool = false,
                       deletePassword: (String) -> Bool = { KeychainHelper.deletePassword(account: $0) }) throws {
        guard store.accounts.contains(username) else { return }
        guard !isInUse, store.session?.username != username else { throw AccountError.accountInUse }
        guard deletePassword(username) else { throw AccountError.keychainFailure }
        store.removeAccount(username)
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
