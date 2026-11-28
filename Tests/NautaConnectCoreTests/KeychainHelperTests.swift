import Security
import XCTest
@testable import NautaConnectCore

final class KeychainHelperTests: XCTestCase {
    func testExistingPasswordIsUpdatedWithoutAdding() {
        let password = " fake password ñ "
        var updates = 0
        let status = KeychainHelper.savePasswordStatus(password, account: "user@nauta.com.cu", update: { query, attributes in
            updates += 1
            XCTAssertEqual(query[kSecAttrService as String] as? String, "com.nautaconnect.macos")
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "user@nauta.com.cu")
            XCTAssertNil(query[kSecValueData as String])
            XCTAssertEqual(attributes.count, 1)
            XCTAssertEqual(attributes[kSecValueData as String] as? Data, Data(password.utf8))
            return errSecSuccess
        }, add: { _ in XCTFail("Existing entry must not be added again"); return errSecDuplicateItem })
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertEqual(updates, 1)
    }

    func testMissingPasswordIsAddedAfterUpdateReportsNotFound() {
        var operations: [String] = []
        let status = KeychainHelper.savePasswordStatus("fake", account: "user@nauta.co.cu", update: { _, _ in
            operations.append("update")
            return errSecItemNotFound
        }, add: { query in
            operations.append("add")
            XCTAssertEqual(query[kSecAttrService as String] as? String, "com.nautaconnect.macos")
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "user@nauta.co.cu")
            XCTAssertEqual(query[kSecValueData as String] as? Data, Data("fake".utf8))
            return errSecSuccess
        })
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertEqual(operations, ["update", "add"])
    }

    func testUpdateErrorsAreReturnedWithoutAttemptingAdd() {
        for expected in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecNotAvailable] {
            let status = KeychainHelper.savePasswordStatus("fake", account: "user", update: { _, _ in expected }, add: { _ in
                XCTFail("A failed update must not be replaced with add")
                return errSecSuccess
            })
            XCTAssertEqual(status, expected)
        }
    }

    func testAddFailurePreservesItsActualStatus() {
        let status = KeychainHelper.savePasswordStatus("fake", account: "user", update: { _, _ in errSecItemNotFound },
                                                      add: { _ in errSecInteractionNotAllowed })
        XCTAssertEqual(status, errSecInteractionNotAllowed)
    }

    func testConcurrentCreationRetriesUpdateOnce() {
        var operations: [String] = []
        var updateCount = 0
        let status = KeychainHelper.savePasswordStatus("fake", account: "user", update: { _, _ in
            operations.append("update")
            updateCount += 1
            return updateCount == 1 ? errSecItemNotFound : errSecSuccess
        }, add: { _ in operations.append("add"); return errSecDuplicateItem })
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertEqual(operations, ["update", "add", "update"])
    }

    func testConflictRetryIsBoundedAndRetainsAuthorizationError() {
        var updates = 0
        var adds = 0
        let status = KeychainHelper.savePasswordStatus("fake", account: "user", update: { _, _ in
            updates += 1
            return updates == 1 ? errSecItemNotFound : errSecAuthFailed
        }, add: { _ in adds += 1; return errSecDuplicateItem })
        XCTAssertEqual(status, errSecAuthFailed)
        XCTAssertEqual(updates, 2)
        XCTAssertEqual(adds, 1)
    }

    func testAccountRegistrationPreservesStatusAndPersistedDataOnFailure() throws {
        let name = "com.nautaconnect.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionStore(defaults: defaults)
        store.username = "existing@nauta.com.cu"
        let before = NSDictionary(dictionary: defaults.persistentDomain(forName: name)!)
        let manager = AccountManager(store: store, savePasswordStatus: { _, _ in errSecAuthFailed })
        XCTAssertThrowsError(try manager.add(username: "new@nauta.co.cu", password: "fake")) {
            XCTAssertEqual(($0 as? KeychainSaveError)?.status, errSecAuthFailed)
        }
        XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: name)!), before)
    }

    func testStatusBasedWriterRegistersOnlyAfterSuccessAndStillRejectsDuplicates() throws {
        let name = "com.nautaconnect.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionStore(defaults: defaults)
        var writes = 0
        let manager = AccountManager(store: store, savePasswordStatus: { password, account in
            writes += 1
            XCTAssertEqual(password, "fake")
            XCTAssertEqual(account, "user@nauta.com.cu")
            return errSecSuccess
        })
        try manager.add(username: " user@nauta.com.cu ", password: "fake")
        XCTAssertEqual(store.accounts, ["user@nauta.com.cu"])
        XCTAssertEqual(store.username, "user@nauta.com.cu")
        XCTAssertThrowsError(try manager.add(username: "USER@nauta.com.cu", password: "replacement")) {
            guard case AccountError.duplicate = $0 else { return XCTFail("Expected duplicate") }
        }
        XCTAssertEqual(writes, 1)
    }
}
