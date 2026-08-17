import XCTest
import Combine
@testable import SmartAirKey

/// Verifies the key rule: seamless access cannot be turned on until **every**
/// access (Bluetooth *and* "Always" location) is granted, and that it finishes
/// enabling automatically once the user grants everything.
@MainActor
final class HomeViewModelTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    private func makeViewModel(
        bluetooth: BluetoothAvailability,
        location: LocationAvailability,
        preferences: InMemoryPreferences = InMemoryPreferences()
    ) -> (HomeViewModel, FakeBluetoothAuth, FakeLocationAuth, MockAccessService) {
        let bt = FakeBluetoothAuth(bluetooth)
        let loc = FakeLocationAuth(location)
        let access = MockAccessService(preferences: preferences, analytics: SpyAnalytics())
        let vm = HomeViewModel(access: access,
                               bluetoothAuth: bt,
                               locationAuth: loc,
                               analytics: SpyAnalytics(),
                               keyProvider: EmptyKeyProvider(),
                               config: .demo)
        return (vm, bt, loc, access)
    }

    /// Bluetooth ready but location only "While Using" → must NOT enable.
    func testEnableBlockedWhenLocationIsOnlyWhenInUse() {
        let (vm, bt, loc, access) = makeViewModel(bluetooth: .ready, location: .whenInUseOnly)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn, "switch must stay off until all access is granted")
        XCTAssertFalse(access.isSeamlessAccessEnabled, "feature must not be enabled")
        XCTAssertTrue(vm.pendingEnable, "the intent to enable should be remembered")
        XCTAssertGreaterThanOrEqual(bt.requestCount, 1, "Bluetooth should be requested")
        XCTAssertGreaterThanOrEqual(loc.requestCount, 1, "location should be requested")
    }

    /// Bluetooth ready but location fully denied → must NOT enable. Only
    /// "Always" location unlocks the feature.
    func testEnableBlockedWhenLocationDenied() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .ready, location: .denied)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// A pending enable must stay blocked if location only reaches "While Using"
    /// — "Always" is mandatory for opening doors while the app is closed.
    func testPendingEnableStaysBlockedWithWhenInUseLocation() {
        let (vm, bt, loc, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)
        bt.set(.ready)
        loc.set(.whenInUseOnly) // upgraded, but not all the way to "Always".

        let settled = expectation(description: "pipeline settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2.0)

        XCTAssertFalse(vm.isSeamlessOn, "When-In-Use is not enough; needs Always")
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// Location "Always" but Bluetooth denied → must NOT enable.
    func testEnableBlockedWhenBluetoothDenied() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .denied, location: .ready)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// Nothing decided yet → blocked, prompts fired, no error surfaced yet.
    func testEnableBlockedWhenAccessUndetermined() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
        XCTAssertNil(vm.activeError, "no error while the system prompts are still pending")
    }

    /// Both Bluetooth ready and location "Always" → enables immediately.
    func testEnableSucceedsWhenAllAccessGranted() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .ready, location: .ready)

        vm.setSeamless(true)

        XCTAssertTrue(vm.isSeamlessOn)
        XCTAssertTrue(access.isSeamlessAccessEnabled)
        XCTAssertFalse(vm.pendingEnable)
    }

    /// After a blocked attempt, granting the remaining access finishes enabling
    /// automatically — the user doesn't have to toggle again.
    func testPendingEnableCompletesOnceAllAccessGranted() {
        let (vm, bt, loc, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)
        XCTAssertTrue(vm.pendingEnable)
        XCTAssertFalse(vm.isSeamlessOn)

        let enabled = expectation(description: "auto-enabled once all access granted")
        vm.$isSeamlessOn
            .filter { $0 }
            .sink { _ in enabled.fulfill() }
            .store(in: &cancellables)

        bt.set(.ready)
        loc.set(.ready)

        wait(for: [enabled], timeout: 2.0)
        XCTAssertTrue(vm.isSeamlessOn)
        XCTAssertTrue(access.isSeamlessAccessEnabled)
        XCTAssertFalse(vm.pendingEnable)
    }

    /// Granting only part of the access must NOT auto-enable.
    func testPendingEnableStaysBlockedWithPartialAccess() {
        let (vm, bt, _, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)
        bt.set(.ready) // Bluetooth granted, location still undetermined.

        // Give the async pipeline a moment; nothing should flip on.
        let settled = expectation(description: "pipeline settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2.0)

        XCTAssertFalse(vm.isSeamlessOn, "must not enable without location Always")
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// Turning it off is always allowed and clears any pending intent.
    func testDisableAlwaysWorks() {
        let prefs = InMemoryPreferences()
        prefs.isSeamlessAccessEnabled = true
        let (vm, _, _, access) = makeViewModel(bluetooth: .ready, location: .ready, preferences: prefs)
        XCTAssertTrue(vm.isSeamlessOn)

        vm.setSeamless(false)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertFalse(vm.pendingEnable)
    }

    /// The home screen requests both Bluetooth and location up front (item 1).
    func testOnAppearRequestsBluetoothAndLocation() {
        let (vm, bt, loc, _) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.onAppear()

        XCTAssertGreaterThanOrEqual(bt.requestCount, 1)
        XCTAssertGreaterThanOrEqual(loc.requestCount, 1)
    }

    /// A backend auth failure (user not found / token invalid) signs the user
    /// out instead of leaving them stuck on the home screen.
    func testUnauthorizedResponseSignsOut() async {
        var signedOut = false
        let vm = HomeViewModel(
            access: MockAccessService(preferences: InMemoryPreferences(), analytics: SpyAnalytics()),
            bluetoothAuth: FakeBluetoothAuth(.ready),
            locationAuth: FakeLocationAuth(.ready),
            analytics: SpyAnalytics(),
            keyProvider: UnauthorizedKeyProvider(),
            config: .demo,
            hasValidToken: { true },
            onAuthenticationLost: { signedOut = true }
        )

        await vm.refreshKeys()

        XCTAssertTrue(signedOut, "a 401/unauthorized should force sign-out")
        XCTAssertNil(vm.activeError, "no generic error alert when signing out")
    }
}

// MARK: - Test doubles

final class FakeBluetoothAuth: BluetoothAuthorizing {
    private let subject: CurrentValueSubject<BluetoothAvailability, Never>
    private(set) var requestCount = 0

    init(_ initial: BluetoothAvailability) {
        subject = CurrentValueSubject(initial)
    }

    var availability: BluetoothAvailability { subject.value }
    var availabilityPublisher: AnyPublisher<BluetoothAvailability, Never> {
        subject.eraseToAnyPublisher()
    }
    func requestAuthorization() { requestCount += 1 }
    func set(_ value: BluetoothAvailability) { subject.send(value) }
}

final class FakeLocationAuth: LocationAuthorizing {
    private let subject: CurrentValueSubject<LocationAvailability, Never>
    private(set) var requestCount = 0

    init(_ initial: LocationAvailability) {
        subject = CurrentValueSubject(initial)
    }

    var availability: LocationAvailability { subject.value }
    var availabilityPublisher: AnyPublisher<LocationAvailability, Never> {
        subject.eraseToAnyPublisher()
    }
    func requestAlwaysAuthorization() { requestCount += 1 }
    func set(_ value: LocationAvailability) { subject.send(value) }
}

final class UnauthorizedKeyProvider: KeyProviding {
    func fetchDigitalKeys() async throws -> Data { throw BackendError.unauthorized }
}

final class EmptyKeyProvider: KeyProviding {
    func fetchDigitalKeys() async throws -> Data { Data("[]".utf8) }
}
