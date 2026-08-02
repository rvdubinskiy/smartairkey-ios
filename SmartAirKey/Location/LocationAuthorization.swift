import Foundation
import Combine
import CoreLocation

/// User-facing location availability. No CoreLocation types leak past here.
///
/// Seamless access must keep opening doors even when the app is closed or
/// evicted from memory, which on iOS requires **Always** location access — so
/// merely being authorized "while in use" is not enough and is reported
/// separately so we can nudge the user to upgrade.
enum LocationAvailability: Equatable {
    /// Not yet determined / still resolving.
    case unknown
    /// Authorized "Always" — doors can be reached in the background.
    case ready
    /// Authorized only "While Using the App" — needs upgrading to "Always".
    case whenInUseOnly
    /// The user denied (or restricted) location access for this app.
    case denied

    /// The actionable error to show, if any (UI req. 4).
    var error: AccessError? {
        switch self {
        case .ready, .unknown: return nil
        case .whenInUseOnly: return .locationWhenInUseOnly
        case .denied: return .locationDenied
        }
    }
}

/// Wraps `CLLocationManager` to (a) request **Always** location authorization —
/// staged the way iOS expects — and (b) publish a plain-language availability
/// state. It also starts significant-location-change monitoring so the system
/// can revive the app in the background to open doors, even after it has been
/// closed or evicted from memory (the key scenario for seamless access).
final class LocationAuthorization: NSObject, ObservableObject {

    @Published private(set) var availability: LocationAvailability = .unknown

    private let manager: CLLocationManager
    /// iOS only lets us prompt for "Always" once; guard so we don't spam it.
    private var didRequestAlways = false

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        evaluate(manager.authorizationStatus)
    }

    /// Requests **Always** location access.
    ///
    /// iOS grants "Always" in two steps: the app first asks for "While Using",
    /// and only afterwards may it ask to upgrade to "Always". We follow that
    /// flow — request When-In-Use when undetermined, then upgrade — and, once
    /// granted, immediately start background monitoring.
    func requestAlwaysAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysUpgrade()
        case .authorizedAlways:
            startMonitoring()
        default:
            evaluate(manager.authorizationStatus)
        }
    }

    /// Starts background-friendly monitoring so iOS can wake the app to open
    /// doors even after it has been closed or evicted. Significant-change
    /// monitoring relaunches a terminated app; no-ops until "Always" is granted.
    func startMonitoring() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startMonitoringSignificantLocationChanges()
    }

    private func requestAlwaysUpgrade() {
        guard !didRequestAlways else { return }
        didRequestAlways = true
        manager.requestAlwaysAuthorization()
    }

    private func evaluate(_ status: CLAuthorizationStatus) {
        let newValue: LocationAvailability
        switch status {
        case .authorizedAlways:
            newValue = .ready
        case .authorizedWhenInUse:
            newValue = .whenInUseOnly
        case .denied, .restricted:
            newValue = .denied
        case .notDetermined:
            newValue = .unknown
        @unknown default:
            newValue = .unknown
        }

        DispatchQueue.main.async { [weak self] in
            self?.availability = newValue
        }
        AppLog.location.info("Location availability=\(String(describing: newValue), privacy: .public)")
    }
}

extension LocationAuthorization: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // Once the user grants "While Using", immediately ask to upgrade to
        // "Always"; once "Always" is granted, begin background monitoring.
        switch status {
        case .authorizedWhenInUse: requestAlwaysUpgrade()
        case .authorizedAlways: startMonitoring()
        default: break
        }
        evaluate(status)
    }
}
