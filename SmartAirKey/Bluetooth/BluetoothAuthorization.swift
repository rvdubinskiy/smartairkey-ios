import Foundation
import Combine
import CoreBluetooth

/// User-facing Bluetooth availability. No CoreBluetooth types leak past here.
enum BluetoothAvailability: Equatable {
    /// Not yet determined / powering up.
    case unknown
    /// Everything is fine — doors can be reached.
    case ready
    /// Bluetooth is switched off.
    case off
    /// The user denied Bluetooth permission for this app.
    case denied
    /// This device can't use Bluetooth for access.
    case unsupported

    /// The actionable error to show, if any (UI req. 4).
    var error: AccessError? {
        switch self {
        case .ready, .unknown: return nil
        case .off: return .bluetoothOff
        case .denied: return .bluetoothDenied
        case .unsupported: return .bluetoothUnsupported
        }
    }
}

/// Abstraction over Bluetooth authorization so view models can read the current
/// state, observe changes, and trigger the permission prompt — and so tests can
/// substitute a fake without CoreBluetooth.
protocol BluetoothAuthorizing: AnyObject {
    var availability: BluetoothAvailability { get }
    var availabilityPublisher: AnyPublisher<BluetoothAvailability, Never> { get }
    /// Whether iOS can still show the *native* Bluetooth permission prompt
    /// (status not determined). Once the user has denied it, iOS won't ask
    /// again and only Settings can re-enable it.
    var canPromptForAuthorization: Bool { get }
    func requestAuthorization()
}

/// Wraps `CBCentralManager` to (a) prompt for Bluetooth permission and (b)
/// publish a plain-language availability state (req. 6).
final class BluetoothAuthorization: NSObject, ObservableObject {

    @Published private(set) var availability: BluetoothAvailability = .unknown

    private var manager: CBCentralManager?

    /// Creates the central manager, which triggers the system permission prompt
    /// on first use. `ShowPowerAlert = true` lets iOS present its native
    /// "Turn On Bluetooth" alert when the radio is off — its **Settings** button
    /// deep-links straight to the Bluetooth screen (the on/off toggle the user
    /// needs), which no public URL can reach. Our own banner/alert complements it.
    func requestAuthorization() {
        guard manager == nil else {
            // Re-evaluate current state.
            centralManagerDidUpdateState(manager!)
            return
        }
        manager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }
}

extension BluetoothAuthorization: BluetoothAuthorizing {
    var availabilityPublisher: AnyPublisher<BluetoothAvailability, Never> {
        $availability.eraseToAnyPublisher()
    }

    var canPromptForAuthorization: Bool {
        CBCentralManager.authorization == .notDetermined
    }
}

extension BluetoothAuthorization: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newValue: BluetoothAvailability
        switch central.state {
        case .poweredOn:
            newValue = .ready
        case .poweredOff:
            newValue = .off
        case .unauthorized:
            newValue = .denied
        case .unsupported:
            newValue = .unsupported
        case .resetting, .unknown:
            newValue = .unknown
        @unknown default:
            newValue = .unknown
        }

        DispatchQueue.main.async { [weak self] in
            self?.availability = newValue
        }
        AppLog.bluetooth.info("Bluetooth availability=\(String(describing: newValue), privacy: .public)")
    }
}
