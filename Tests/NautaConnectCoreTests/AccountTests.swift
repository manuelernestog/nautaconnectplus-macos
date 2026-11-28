import XCTest
@testable import NautaConnectCore

final class AccountTests: XCTestCase {
    private func withStore(_ body: (SessionStore, UserDefaults) throws -> Void) rethrows {
        let name = "com.nautaconnect.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(SessionStore(defaults: defaults), defaults)
    }

    func testLegacyAccountAndSessionSurviveAddingAccounts() throws {
        try withStore { store, defaults in
            store.username = "first@nauta.com.cu"
            let session = Self.session(store.username)
            store.session = session
            XCTAssertEqual(store.accounts, [store.username])
            let accounts = AccountManager(store: store, savePassword: { _, _ in true })
            try accounts.add(username: " second@nauta.com.cu \n", password: "secret")
            let restored = SessionStore(defaults: defaults)
            XCTAssertEqual(restored.accounts, ["first@nauta.com.cu", "second@nauta.com.cu"])
            XCTAssertEqual(restored.username, "first@nauta.com.cu")
            XCTAssertEqual(restored.session, session)
            XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "secret" })
        }
    }

    func testAccountValidationAndKeychainFailureDoNotPersistAccounts() throws {
        try withStore { store, _ in
            var writes = 0
            let accounts = AccountManager(store: store, savePassword: { _, _ in writes += 1; return false })
            XCTAssertThrowsError(try accounts.add(username: "  ", password: "secret"))
            XCTAssertThrowsError(try accounts.add(username: "first", password: ""))
            XCTAssertEqual(writes, 0)
            XCTAssertThrowsError(try accounts.add(username: "first", password: "secret"))
            XCTAssertEqual(writes, 1)
            XCTAssertTrue(store.accounts.isEmpty)
            XCTAssertTrue(store.username.isEmpty)
        }
    }

    func testFirstAccountSelectionAndDuplicateRejection() throws {
        try withStore { store, _ in
            var writes = 0
            let accounts = AccountManager(store: store, savePassword: { _, _ in writes += 1; return true })
            try accounts.add(username: "first@nauta.com.cu", password: "secret")
            XCTAssertEqual(store.username, "first@nauta.com.cu")
            XCTAssertThrowsError(try accounts.add(username: " FIRST@nauta.com.cu ", password: "replacement"))
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(store.accounts, ["first@nauta.com.cu"])
        }
    }

    @MainActor
    func testSwitchLogsOutBeforeLoginAndPersistsNewSession() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let old = Self.session("first")
        store.username = old.username
        store.session = old
        var events: [String] = []
        let connector = AccountConnector(store: store, login: { username, _ in
            XCTAssertNil(store.session)
            events.append("login:\(username)")
            return Self.session(username)
        }, logout: { session in
            XCTAssertEqual(store.session, old)
            events.append("logout:\(session.username)")
        })
        try await connector.connect(username: "second", password: "secret")
        XCTAssertEqual(events, ["logout:first", "login:second"])
        XCTAssertEqual(store.session?.username, "second")
        XCTAssertEqual(store.username, "second")
        XCTAssertFalse(connector.isBusy)
    }

    @MainActor
    func testLogoutFailurePreservesOldAccountAndDoesNotLogin() async {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let old = Self.session("first")
        store.username = "first"
        store.session = old
        let connector = AccountConnector(store: store, login: { _, _ in
            XCTFail("Must not log in after failed logout")
            return Self.session("second")
        }, logout: { _ in throw PortalError.badResponse })
        do {
            try await connector.connect(username: "second", password: "secret")
            XCTFail("Expected failed logout")
        } catch {}
        XCTAssertEqual(store.session, old)
        XCTAssertEqual(store.username, "first")
        XCTAssertFalse(connector.isBusy)
    }

    @MainActor
    func testLoginFailureAfterLogoutLeavesDisconnected() async {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.username = "first"
        store.session = Self.session("first")
        let connector = AccountConnector(store: store, login: { _, _ in throw PortalError.badResponse }, logout: { _ in })
        do {
            try await connector.connect(username: "second", password: "secret")
            XCTFail("Expected failed login")
        } catch {}
        XCTAssertNil(store.session)
        XCTAssertEqual(store.username, "second")
        XCTAssertFalse(connector.isBusy)
    }

    @MainActor
    func testSingleAccountConnectAndSelectingCurrentAccount() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        var logins = 0
        let connector = AccountConnector(store: store, login: { username, _ in
            logins += 1
            return Self.session(username)
        }, logout: { _ in XCTFail("Current account must not be logged out") })
        try await connector.connect(username: "first", password: "secret")
        try await connector.connect(username: "first", password: "secret")
        XCTAssertEqual(logins, 1)
        XCTAssertEqual(store.session?.username, "first")
    }

    @MainActor
    func testOverlappingSwitchIsRejected() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        var resume: CheckedContinuation<Void, Never>?
        let connector = AccountConnector(store: store, login: { username, _ in
            await withCheckedContinuation { resume = $0 }
            return Self.session(username)
        }, logout: { _ in })
        let first = Task { try await connector.connect(username: "first", password: "secret") }
        while resume == nil { await Task.yield() }
        do {
            try await connector.connect(username: "second", password: "secret")
            XCTFail("Expected busy rejection")
        } catch {}
        resume?.resume()
        try await first.value
        XCTAssertEqual(store.session?.username, "first")
    }

    private func makeStore() -> (SessionStore, UserDefaults, String) {
        let name = "com.nautaconnect.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (SessionStore(defaults: defaults), defaults, name)
    }

    private static func session(_ username: String) -> PortalSession {
        PortalSession(username: username, csrfhw: "test", wlanUserIP: "192.0.2.1", attributeUUID: "test", loginDate: Date(timeIntervalSince1970: 0))
    }
}
