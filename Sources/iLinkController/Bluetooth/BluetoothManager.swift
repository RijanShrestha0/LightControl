import CoreBluetooth
import Combine
import Foundation

enum BLEConnectionAttemptResult {
    case connected
    case noSelectedDevice
    case permissionDenied
    case bluetoothUnavailable
    case alreadyConnecting
    case anotherDeviceConnected
    case timedOut
    case failed
}

final class BluetoothManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var services: [BLEServiceSnapshot] = []
    @Published private(set) var connectedDeviceID: UUID?
    @Published private(set) var connectingDeviceID: UUID?
    @Published private(set) var failedConnectionDeviceID: UUID?
    @Published private(set) var isDiscoveringServices = false
    @Published private(set) var connectionMessage = "Not connected"
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

    private var central: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var hasScanned = false
    private let selectedPeripheralIDKey = "com.ilinkcontroller.selectedBluetoothPeripheralID"
    private var pendingConnectionID: UUID?
    private var pendingPeripheral: CBPeripheral?
    private var pendingConnectionContinuation: CheckedContinuation<BLEConnectionAttemptResult, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?

    var selectedPeripheralID: UUID? {
        guard let value = UserDefaults.standard.string(forKey: selectedPeripheralIDKey) else { return nil }
        return UUID(uuidString: value)
    }

    var activePeripheralIdentifier: UUID? {
        connectedDeviceID ?? connectingDeviceID ?? failedConnectionDeviceID ?? selectedPeripheralID
    }

    var activePeripheralName: String? {
        guard let activePeripheralIdentifier else { return nil }
        return connectedPeripheral?.name
            ?? devices.first(where: { $0.id == activePeripheralIdentifier })?.name
    }

    func waitForBluetoothState() async {
        for _ in 0..<25 where bluetoothState == .unknown || bluetoothState == .resetting {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var bluetoothStateDescription: String {
        switch bluetoothState {
        case .poweredOn: "Bluetooth On"
        case .poweredOff: "Bluetooth Off"
        case .unauthorized: "Bluetooth Access Denied"
        case .unsupported: "Bluetooth Unavailable"
        case .resetting: "Bluetooth Resetting"
        case .unknown: "Checking Bluetooth"
        @unknown default: "Bluetooth Status Unknown"
        }
    }

    var scanStatusMessage: String {
        switch bluetoothState {
        case .unauthorized:
            "Bluetooth permission denied. Allow access in System Settings."
        case .poweredOff:
            "Bluetooth is off. Turn it on to scan."
        case .unsupported:
            "Bluetooth is unavailable on this Mac."
        case .resetting:
            "Bluetooth is resetting."
        case .unknown:
            "Checking Bluetooth availability."
        case .poweredOn where isScanning:
            "Scanning for nearby devices..."
        case .poweredOn where hasScanned:
            devices.isEmpty ? "Scan stopped. No devices found." : "Scan stopped. \(devices.count) devices found."
        case .poweredOn:
            "Ready to scan."
        @unknown default:
            "Bluetooth status is unavailable."
        }
    }

    func connectionStatus(for device: BluetoothDevice) -> String {
        if connectedDeviceID == device.id { return "Connected" }
        if connectingDeviceID == device.id { return "Connecting" }
        if failedConnectionDeviceID == device.id { return "Connection failed" }
        return "Available"
    }

    func startScan() {
        guard bluetoothState == .poweredOn, let central else { return }
        devices = []
        errorMessage = nil
        hasScanned = true
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func connect(to device: BluetoothDevice) {
        guard let central else { return }
        UserDefaults.standard.set(device.id.uuidString, forKey: selectedPeripheralIDKey)
        stopScan()
        errorMessage = nil
        services = []
        failedConnectionDeviceID = nil
        connectingDeviceID = device.id
        isDiscoveringServices = false
        connectionMessage = "Connecting to \(device.name)..."
        connectedPeripheral = device.peripheral
        central.connect(device.peripheral, options: nil)
    }

    func connectToSelectedDevice() async -> BLEConnectionAttemptResult {
        guard let central else { return .bluetoothUnavailable }
        await waitForBluetoothState()
        switch bluetoothState {
        case .unauthorized:
            return .permissionDenied
        case .poweredOn:
            break
        default:
            return .bluetoothUnavailable
        }

        guard let selectedPeripheralID else { return .noSelectedDevice }
        if connectedDeviceID == selectedPeripheralID { return .connected }
        if connectingDeviceID == selectedPeripheralID { return .alreadyConnecting }
        if connectedPeripheral != nil { return .anotherDeviceConnected }

        let peripheral = central.retrievePeripherals(withIdentifiers: [selectedPeripheralID]).first
        return await withCheckedContinuation { continuation in
            pendingConnectionID = selectedPeripheralID
            pendingPeripheral = peripheral
            pendingConnectionContinuation = continuation
            connectingDeviceID = selectedPeripheralID
            failedConnectionDeviceID = nil
            connectionMessage = "Connecting to selected device..."
            connectionTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self else { return }
                self.connectionTimedOut(for: selectedPeripheralID)
            }

            if let peripheral {
                central.connect(peripheral, options: nil)
            } else {
                isScanning = true
                central.scanForPeripherals(withServices: nil, options: nil)
            }
        }
    }

    private func connectionTimedOut(for identifier: UUID) {
        guard pendingConnectionID == identifier else { return }
        if let pendingPeripheral {
            central?.cancelPeripheralConnection(pendingPeripheral)
        }
        finishPendingConnection(with: .timedOut)
        connectingDeviceID = nil
        failedConnectionDeviceID = identifier
        connectionMessage = "Connection timed out"
    }

    private func finishPendingConnection(with result: BLEConnectionAttemptResult) {
        guard let continuation = pendingConnectionContinuation else { return }
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        pendingConnectionContinuation = nil
        pendingConnectionID = nil
        pendingPeripheral = nil
        if isScanning {
            central?.stopScan()
            isScanning = false
        }
        continuation.resume(returning: result)
    }

    func disconnect() {
        guard let connectedPeripheral else { return }
        central?.cancelPeripheralConnection(connectedPeripheral)
    }

    private func propertyNames(for properties: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if properties.contains(.read) { names.append("Read") }
        if properties.contains(.write) { names.append("Write") }
        if properties.contains(.writeWithoutResponse) { names.append("Write Without Response") }
        if properties.contains(.notify) { names.append("Notify") }
        if properties.contains(.indicate) { names.append("Indicate") }
        if properties.contains(.authenticatedSignedWrites) { names.append("Signed Write") }
        if properties.contains(.broadcast) { names.append("Broadcast") }
        if properties.contains(.extendedProperties) { names.append("Extended Properties") }
        return names
    }

    private func recordValue(_ value: Data?, characteristic: CBCharacteristic) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == characteristic.service?.uuid.uuidString }),
              let characteristicIndex = services[serviceIndex].characteristics.firstIndex(where: { $0.id == characteristic.uuid.uuidString }) else {
            return
        }
        services[serviceIndex].characteristics[characteristicIndex].value = Self.hexString(value) ?? "Empty value"
        services[serviceIndex].characteristics[characteristicIndex].isReadPending = false
        services[serviceIndex].characteristics[characteristicIndex].readError = nil
    }

    private static func hexString(_ data: Data?) -> String? {
        data.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }
    }

    private func characteristicSnapshot(for characteristic: CBCharacteristic) -> (serviceIndex: Int, characteristicIndex: Int)? {
        guard let serviceID = characteristic.service?.uuid.uuidString,
              let serviceIndex = services.firstIndex(where: { $0.id == serviceID }),
              let characteristicIndex = services[serviceIndex].characteristics.firstIndex(where: { $0.id == characteristic.uuid.uuidString }) else {
            return nil
        }
        return (serviceIndex, characteristicIndex)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state != .poweredOn {
            isScanning = false
            failedConnectionDeviceID = connectingDeviceID
            connectingDeviceID = nil
            finishPendingConnection(with: central.state == .unauthorized ? .permissionDenied : .bluetoothUnavailable)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unnamed device"
        let previousDevice = devices.first(where: { $0.id == peripheral.identifier })
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
            .sorted()
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let device = BluetoothDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            peripheral: peripheral,
            advertisedServiceUUIDs: serviceUUIDs.isEmpty ? previousDevice?.advertisedServiceUUIDs ?? [] : serviceUUIDs,
            manufacturerDataHex: Self.hexString(manufacturerData) ?? previousDevice?.manufacturerDataHex
        )

        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        devices.sort { $0.rssi > $1.rssi }

        if pendingConnectionID == peripheral.identifier {
            stopScan()
            pendingPeripheral = peripheral
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectingDeviceID = nil
        failedConnectionDeviceID = nil
        connectedDeviceID = peripheral.identifier
        isDiscoveringServices = true
        connectionMessage = "Connected to \(peripheral.name ?? "device")"
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        if pendingConnectionID == peripheral.identifier {
            finishPendingConnection(with: .connected)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        connectingDeviceID = nil
        connectedDeviceID = nil
        isDiscoveringServices = false
        failedConnectionDeviceID = peripheral.identifier
        connectionMessage = "Connection failed"
        errorMessage = error?.localizedDescription ?? "The device could not be connected."
        if pendingConnectionID == peripheral.identifier {
            finishPendingConnection(with: .failed)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        connectingDeviceID = nil
        connectedDeviceID = nil
        isDiscoveringServices = false
        services = []
        connectionMessage = "Disconnected"
        if let error {
            errorMessage = error.localizedDescription
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        isDiscoveringServices = false
        if let error {
            errorMessage = "Service discovery failed: \(error.localizedDescription)"
            return
        }
        guard let discoveredServices = peripheral.services else { return }
        services = discoveredServices.map {
            BLEServiceSnapshot(id: $0.uuid.uuidString, characteristics: [], isDiscoveringCharacteristics: true)
        }
        discoveredServices.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let serviceIndex = services.firstIndex(where: { $0.id == service.uuid.uuidString }) else { return }
        services[serviceIndex].isDiscoveringCharacteristics = false

        if let error {
            let message = error.localizedDescription
            services[serviceIndex].discoveryError = message
            errorMessage = "Characteristic discovery failed: \(message)"
            return
        }

        guard let characteristics = service.characteristics else { return }
        services[serviceIndex].characteristics = characteristics.map { characteristic in
            let canNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            return BLECharacteristicSnapshot(
                id: characteristic.uuid.uuidString,
                properties: propertyNames(for: characteristic.properties),
                value: nil,
                isReadPending: characteristic.properties.contains(.read),
                notificationStatus: canNotify ? "Subscribing" : "Not supported"
            )
        }

        for characteristic in characteristics {
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let index = characteristicSnapshot(for: characteristic) else { return }
        if let error {
            services[index.serviceIndex].characteristics[index.characteristicIndex].isReadPending = false
            services[index.serviceIndex].characteristics[index.characteristicIndex].readError = error.localizedDescription
            return
        }
        recordValue(characteristic.value, characteristic: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let index = characteristicSnapshot(for: characteristic) else { return }
        if let error {
            services[index.serviceIndex].characteristics[index.characteristicIndex].notificationStatus = "Unavailable"
            services[index.serviceIndex].characteristics[index.characteristicIndex].notificationError = error.localizedDescription
            return
        }
        services[index.serviceIndex].characteristics[index.characteristicIndex].notificationStatus = characteristic.isNotifying ? "Active" : "Inactive"
        services[index.serviceIndex].characteristics[index.characteristicIndex].notificationError = nil
    }
}