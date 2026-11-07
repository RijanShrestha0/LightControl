import CoreBluetooth

struct BluetoothDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
    var advertisedServiceUUIDs: [String] = []
    var manufacturerDataHex: String?
}

struct BLEServiceSnapshot: Identifiable {
    let id: String
    var characteristics: [BLECharacteristicSnapshot]
    var isDiscoveringCharacteristics = true
    var discoveryError: String?
}

struct BLECharacteristicSnapshot: Identifiable {
    let id: String
    let properties: [String]
    var value: String?
    var isReadPending = false
    var readError: String?
    var notificationStatus = "Not supported"
    var notificationError: String?
}