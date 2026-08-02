import XCTest
@testable import SmartAirKey

/// Verifies the SDK-free geolocation logic: how location authorization states
/// map to user-facing errors. This is what decides when the app nudges the user
/// to grant "Always" access so doors keep opening with the app closed (req. 7).
final class LocationAuthorizationTests: XCTestCase {

    /// "Always" is the only state that lets seamless access work in the
    /// background, so it must be the only granted state with no error.
    func testAlwaysIsReadyWithNoError() {
        XCTAssertNil(LocationAvailability.ready.error)
    }

    /// Still resolving — don't nag the user before iOS has answered.
    func testUnknownHasNoError() {
        XCTAssertNil(LocationAvailability.unknown.error)
    }

    /// "While Using the App" is not enough for background door opening, so it
    /// must surface the "switch to Always" nudge.
    func testWhenInUseOnlyRequestsAlwaysUpgrade() {
        XCTAssertEqual(LocationAvailability.whenInUseOnly.error, .locationWhenInUseOnly)
    }

    /// Denied/restricted must point the user to Settings.
    func testDeniedSurfacesLocationDenied() {
        XCTAssertEqual(LocationAvailability.denied.error, .locationDenied)
    }

    /// Every location error's single primary action opens Settings, where the
    /// user grants or upgrades access (UI req. 4).
    func testLocationErrorsOpenSettings() {
        XCTAssertEqual(LocationAvailability.whenInUseOnly.error?.primaryAction, .openSettings)
        XCTAssertEqual(LocationAvailability.denied.error?.primaryAction, .openSettings)
    }
}
