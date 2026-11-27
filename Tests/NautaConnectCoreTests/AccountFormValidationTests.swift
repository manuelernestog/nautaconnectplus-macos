import XCTest
@testable import NautaConnectCore

final class AccountFormValidationTests: XCTestCase {
    func testOnlyNautaDomainsEnableSaving() {
        for username in ["user@nauta.com.cu", "user@nauta.co.cu", "USER@NAUTA.COM.CU", " user@nauta.co.cu \n"] {
            XCTAssertTrue(AccountFormValidation.canSave(username: username, password: "secret"), username)
        }
        for username in ["", "user", "@nauta.com.cu", "user@gmail.com", "user@nauta.cu",
                         "user@nauta.com.cu.example", "user@sub.nauta.com.cu", "user@@nauta.com.cu",
                         "user name@nauta.com.cu", "user@nauta.co.cu.extra"] {
            XCTAssertFalse(AccountFormValidation.canSave(username: username, password: "secret"), username)
        }
    }

    func testPasswordMustBeNonemptyWithoutChangingItsContents() {
        for username in ["user@nauta.com.cu", "user@nauta.co.cu"] {
            XCTAssertFalse(AccountFormValidation.canSave(username: username, password: ""))
            XCTAssertTrue(AccountFormValidation.canSave(username: username, password: "secret"))
            XCTAssertTrue(AccountFormValidation.canSave(username: username, password: " "))
        }
    }
}
