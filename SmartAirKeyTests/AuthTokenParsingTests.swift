import XCTest
@testable import SmartAirKey

/// The app must NOT authorize unless GetUserToken returned a real user token.
/// Covers the pure parsing/validation used by SmartAirKeyAuthService.signIn.
final class AuthTokenParsingTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testValidResponseYieldsToken() {
        let json = #"{"apiKeyId":"ABC123","token":"tok_xyz"}"#
        XCTAssertEqual(
            SmartAirKeyAuthService.userToken(status: 200, data: data(json)),
            "ABC123:tok_xyz"
        )
    }

    func testEmptyFieldsAreRejected() {
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 200, data: data(#"{"apiKeyId":"","token":""}"#)))
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 200, data: data(#"{"apiKeyId":"ABC","token":""}"#)))
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 200, data: data(#"{"apiKeyId":"","token":"tok"}"#)))
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 200, data: data(#"{"apiKeyId":"  ","token":"tok"}"#)))
    }

    func testMissingFieldsAreRejected() {
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 200, data: data("{}")))
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 200, data: data(#"{"token":"tok"}"#)))
    }

    func testErrorBodyIsRejected() {
        // Unknown user often comes back as 200 + an error envelope.
        let json = #"{"error":"user not found"}"#
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 200, data: data(json)))
    }

    func testNon200IsRejected() {
        let json = #"{"apiKeyId":"ABC","token":"tok"}"#
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 404, data: data(json)))
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 401, data: data(json)))
        XCTAssertNil(SmartAirKeyAuthService.userToken(status: 500, data: data(json)))
    }
}
