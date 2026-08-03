import XCTest
@testable import SmartAirKey

/// The mobile API expects `Authorization: SAS-TOKEN <apiKeyId>:<token>`.
/// A common paste mistake is including the `SAS-TOKEN ` prefix in the token,
/// which used to be doubled and rejected with 401. These lock the fix.
final class AuthorizationHeaderTests: XCTestCase {

    func testBareTokenGetsSchemePrefix() {
        XCTAssertEqual(
            SmartAirKeyBackendClient.authorizationHeader(for: "3685367467:jvZBY72qoq"),
            "SAS-TOKEN 3685367467:jvZBY72qoq"
        )
    }

    func testTokenWithSchemeIsNotDoubled() {
        XCTAssertEqual(
            SmartAirKeyBackendClient.authorizationHeader(for: "SAS-TOKEN 3685367467:jvZBY72qoq"),
            "SAS-TOKEN 3685367467:jvZBY72qoq"
        )
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(
            SmartAirKeyBackendClient.authorizationHeader(for: "  3685367467:jvZBY72qoq \n"),
            "SAS-TOKEN 3685367467:jvZBY72qoq"
        )
    }

    func testExistingSchemeIsCaseInsensitive() {
        XCTAssertEqual(
            SmartAirKeyBackendClient.authorizationHeader(for: "sas-token 3685367467:jvZBY72qoq"),
            "sas-token 3685367467:jvZBY72qoq"
        )
    }
}
