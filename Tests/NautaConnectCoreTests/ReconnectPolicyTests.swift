import XCTest
@testable import NautaConnectCore

final class ReconnectPolicyTests: XCTestCase {
    func testStopsImmediatelyOnWrongCredentialsOrBalance() {
        let error = PortalError.loginRejected("Entre el nombre de usuario y contraseña correctos.")
        XCTAssertEqual(
            ReconnectPolicy.disposition(for: error, attempt: 1),
            .stop(reason: "Entre el nombre de usuario y contraseña correctos.")
        )
    }

    func testRetriesAlreadyConnectedBrieflyThenStops() {
        let error = PortalError.loginRejected("El usuario ya está conectado.")
        XCTAssertEqual(ReconnectPolicy.disposition(for: error, attempt: 1), .retry(delay: 15))
        XCTAssertEqual(ReconnectPolicy.disposition(for: error, attempt: 3), .retry(delay: 60))
        XCTAssertEqual(
            ReconnectPolicy.disposition(for: error, attempt: 4),
            .stop(reason: "El usuario ya está conectado.")
        )
    }

    func testRetriesTransientErrorsWithCappedBackoff() {
        XCTAssertEqual(ReconnectPolicy.disposition(for: PortalError.portalUnreachable, attempt: 1), .retry(delay: 15))
        XCTAssertEqual(ReconnectPolicy.disposition(for: PortalError.badResponse, attempt: 2), .retry(delay: 30))
        XCTAssertEqual(ReconnectPolicy.disposition(for: PortalError.portalUnreachable, attempt: 4), .retry(delay: 120))
        XCTAssertEqual(ReconnectPolicy.disposition(for: PortalError.portalUnreachable, attempt: 6), .retry(delay: 300))
    }

    func testSessionStoreDefaultsAndIntervalValidation() {
        let suiteName = "com.nautaconnect.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionStore(defaults: defaults)
        XCTAssertFalse(store.autoReconnect)
        XCTAssertEqual(store.autoReconnectIntervalSeconds, 60)

        store.autoReconnect = true
        store.autoReconnectIntervalSeconds = 30
        XCTAssertTrue(store.autoReconnect)
        XCTAssertEqual(store.autoReconnectIntervalSeconds, 30)

        store.autoReconnectIntervalSeconds = 999
        XCTAssertEqual(store.autoReconnectIntervalSeconds, 60)
    }
}
