import Combine

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let bluetoothManager: BluetoothManager
    let lightController: LightController

    private init() {
        let bluetoothManager = BluetoothManager()
        self.bluetoothManager = bluetoothManager
        lightController = LightController(bluetoothManager: bluetoothManager)
    }
}