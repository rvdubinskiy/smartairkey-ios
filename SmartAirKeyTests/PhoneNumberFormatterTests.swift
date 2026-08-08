import XCTest
@testable import SmartAirKey

/// Covers the sign-in phone mask/validation (SDK-free).
final class PhoneNumberFormatterTests: XCTestCase {

    func testFormatsProgressively() {
        XCTAssertEqual(PhoneNumberFormatter.format(""), "+7")
        XCTAssertEqual(PhoneNumberFormatter.format("9"), "+7 (9")
        XCTAssertEqual(PhoneNumberFormatter.format("916"), "+7 (916")
        XCTAssertEqual(PhoneNumberFormatter.format("9161"), "+7 (916) 1")
        XCTAssertEqual(PhoneNumberFormatter.format("9161500159"), "+7 (916) 150-01-59")
    }

    func testDropsLeadingCountryCode() {
        // Leading 7, 8 or a pasted +7 are all treated as the country code.
        XCTAssertEqual(PhoneNumberFormatter.format("89161500159"), "+7 (916) 150-01-59")
        XCTAssertEqual(PhoneNumberFormatter.format("+7 916 150 01 59"), "+7 (916) 150-01-59")
        XCTAssertEqual(PhoneNumberFormatter.format("77777777770"), "+7 (777) 777-77-70")
    }

    func testIgnoresExtraDigits() {
        XCTAssertEqual(PhoneNumberFormatter.format("91615001591234"), "+7 (916) 150-01-59")
    }

    func testE164() {
        XCTAssertEqual(PhoneNumberFormatter.e164("9161500159"), "+79161500159")
        XCTAssertEqual(PhoneNumberFormatter.e164("+7 (916) 150-01-59"), "+79161500159")
        XCTAssertEqual(PhoneNumberFormatter.e164("89161500159"), "+79161500159")
        XCTAssertNil(PhoneNumberFormatter.e164("916150"))       // incomplete
        XCTAssertNil(PhoneNumberFormatter.e164(""))
    }

    func testValidity() {
        XCTAssertTrue(PhoneNumberFormatter.isValid("+7 (916) 150-01-59"))
        XCTAssertTrue(PhoneNumberFormatter.isValid("9161500159"))
        XCTAssertFalse(PhoneNumberFormatter.isValid("916150015"))  // 9 digits
        XCTAssertFalse(PhoneNumberFormatter.isValid("+7"))
    }
}
