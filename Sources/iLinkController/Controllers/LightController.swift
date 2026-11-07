import CoreBluetooth
import Foundation

@MainActor
final class LightController {
    private let bluetoothManager: BluetoothManager

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    func connectionStatusResponse() async -> String {
        await bluetoothManager.waitForBluetoothState()

        switch bluetoothManager.bluetoothState {
        case .unauthorized:
            return "Bluetooth access is denied. Allow Bluetooth access for iLink Controller in System Settings."
        case .poweredOff:
            return "Bluetooth is turned off."
        case .unsupported:
            return "Bluetooth is unavailable on this Mac."
        case .unknown, .resetting:
            return "Bluetooth status is not available yet."
        case .poweredOn:
            if let selectedPeripheralID = bluetoothManager.selectedPeripheralID,
               bluetoothManager.connectedDeviceID == selectedPeripheralID {
                return "Your selected Bluetooth device is connected."
            }
            if let selectedPeripheralID = bluetoothManager.selectedPeripheralID,
               bluetoothManager.connectingDeviceID == selectedPeripheralID {
                return "Your selected Bluetooth device is connecting."
            }
            if bluetoothManager.connectedDeviceID != nil {
                return "A different Bluetooth device is connected."
            }
            return bluetoothManager.selectedPeripheralID == nil
                ? "No light has been selected. Open iLink Controller and select a device first."
                : "Your selected Bluetooth device is currently disconnected."
        @unknown default:
            return "Bluetooth status is not available."
        }
    }

    func connect(to device: BluetoothDevice) {
        bluetoothManager.connect(to: device)
    }

    func disconnect() {
        bluetoothManager.disconnect()
    }

    func connectToSelectedLight() async -> String {
        let result = await bluetoothManager.connectToSelectedDevice()
        switch result {
        case .connected:
            return "Connected to your selected Bluetooth device."
        case .noSelectedDevice:
            return "No light has been selected. Open iLink Controller and select a device first."
        case .permissionDenied:
            return "I couldn't connect because Bluetooth access is denied. Allow Bluetooth access for iLink Controller in System Settings."
        case .bluetoothUnavailable:
            return "I couldn't connect because Bluetooth is unavailable or turned off."
        case .alreadyConnecting:
            return "Your selected Bluetooth device is already connecting."
        case .anotherDeviceConnected:
            return "Another Bluetooth device is already connected. Disconnect it before connecting to the selected device."
        case .timedOut:
            return "I couldn't connect to your selected device. Make sure it is nearby and try again."
        case .failed:
            return "I couldn't connect to your selected device."
        }
    }
}