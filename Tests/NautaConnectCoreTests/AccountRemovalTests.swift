import XCTest
@testable import NautaConnectCore

final class AccountRemovalTests: XCTestCase {
    private func withStore(_ body: (SessionStore, UserDefaults, String) throws -> Void) rethrows {
        let name = "com.nautaconnect.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(SessionStore(defaults: defaults), defaults, name)
    }

    private func populate(_ store: SessionStore) throws -> AccountManager {
        let manager = AccountManager(store: store, savePassword: { _, _ in true })
        try manager.add(username: "first@nauta.com.cu", password: "fake")
        try manager.add(username: "second@nauta.co.cu", password: "fake")
        return manager
    }

    func testRemovingUnusedAccountKeepsCurrentSessionAndPreferences() throws {
        try withStore { store, defaults, _ in
            let manager = try populate(store)
            store.autoReconnect = true
            let session = PortalSession(username: store.username, csrfhw: "fake", wlanUserIP: "192.0.2.1",
                                        attributeUUID: "fake", loginDate: Date(timeIntervalSince1970: 0))
            store.session = session
            var deleted: [String] = []
            try manager.remove(username: "second@nauta.co.cu", deletePassword: { deleted.append($0); return true })
            let restored = SessionStore(defaults: defaults)
            XCTAssertEqual(deleted, ["second@nauta.co.cu"])
            XCTAssertEqual(restored.accounts, ["first@nauta.com.cu"])
            XCTAssertEqual(restored.username, "first@nauta.com.cu")
            XCTAssertEqual(restored.session, session)
            XCTAssertTrue(restored.autoReconnect)
        }
    }

    func testRemovingSelectedDisconnectedAccountSelectsRemainingAccount() throws {
        try withStore { store, _, _ in
            let manager = try populate(store)
            try manager.remove(username: "first@nauta.com.cu", deletePassword: { _ in true })
            XCTAssertEqual(store.accounts, ["second@nauta.co.cu"])
            XCTAssertEqual(store.username, "second@nauta.co.cu")
            XCTAssertNil(store.session)
        }
    }

    func testRemovingLastLegacyAccountDoesNotRestoreItOnRelaunch() throws {
        try withStore { store, defaults, _ in
            store.username = "legacy@nauta.com.cu"
            let manager = AccountManager(store: store)
            try manager.remove(username: store.username, deletePassword: { _ in true })
            let restored = SessionStore(defaults: defaults)
            XCTAssertTrue(restored.accounts.isEmpty)
            XCTAssertTrue(restored.username.isEmpty)
            XCTAssertNil(restored.session)
            try AccountManager(store: restored, savePassword: { _, _ in true })
                .add(username: "new@nauta.co.cu", password: "fake")
            XCTAssertEqual(restored.accounts, ["new@nauta.co.cu"])
            XCTAssertEqual(restored.username, "new@nauta.co.cu")
        }
    }

    func testKeychainFailureLeavesAllPersistedDataUnchanged() throws {
        try withStore { store, defaults, name in
            let manager = try populate(store)
            let before = NSDictionary(dictionary: defaults.persistentDomain(forName: name)!)
            XCTAssertThrowsError(try manager.remove(username: store.username, deletePassword: { _ in false })) {
                guard case AccountError.keychainFailure = $0 else { return XCTFail("Unexpected error") }
            }
            XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: name)!), before)
        }
    }

    func testActiveAccountCannotBeRemovedOrTouchKeychain() throws {
        try withStore { store, defaults, name in
            let manager = try populate(store)
            store.session = PortalSession(username: store.username, csrfhw: "fake", wlanUserIP: "192.0.2.1",
                                          attributeUUID: "fake", loginDate: Date(timeIntervalSince1970: 0))
            let before = NSDictionary(dictionary: defaults.persistentDomain(forName: name)!)
            XCTAssertThrowsError(try manager.remove(username: store.username, deletePassword: { _ in
                XCTFail("Must not touch active credentials"); return true
            })) {
                guard case AccountError.accountInUse = $0 else { return XCTFail("Unexpected error") }
            }
            XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: name)!), before)
        }
    }

    func testInFlightAccountCannotBeRemovedEvenWithoutSession() throws {
        try withStore { store, defaults, name in
            let manager = try populate(store)
            let before = NSDictionary(dictionary: defaults.persistentDomain(forName: name)!)
            XCTAssertThrowsError(try manager.remove(username: "second@nauta.co.cu", isInUse: true, deletePassword: { _ in
                XCTFail("Must not touch in-flight credentials"); return true
            })) {
                guard case AccountError.accountInUse = $0 else { return XCTFail("Unexpected error") }
            }
            XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: name)!), before)
        }
    }

    func testRemovingUnknownAccountIsIdempotent() throws {
        try withStore { store, defaults, name in
            let manager = try populate(store)
            let before = NSDictionary(dictionary: defaults.persistentDomain(forName: name)!)
            try manager.remove(username: "missing@nauta.com.cu", deletePassword: { _ in
                XCTFail("Must not delete unregistered credentials"); return true
            })
            XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: name)!), before)
        }
    }
}
