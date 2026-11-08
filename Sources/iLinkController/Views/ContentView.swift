import SwiftUI

struct ContentView: View {
    @ObservedObject var bluetooth: BluetoothManager
    let lightController: LightController
    let glowAssistant: GlowAssistantManager
    @State private var selectedSection = AppSection.glow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if selectedSection == .glow {
                GlowView(assistant: glowAssistant)
            } else {
                HStack(spacing: 0) {
                    deviceList
                        .frame(minWidth: 250, idealWidth: 290, maxWidth: 330)
                    Divider()
                    inspector
                }
            }
        }
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("iLink Controller")
                    .font(.system(size: 18, weight: .semibold))
                Text("Glow · Bluetooth Diagnostics")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Section", selection: $selectedSection) {
                Text("Glow").tag(AppSection.glow)
                Text("Bluetooth").tag(AppSection.bluetooth)
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            Spacer()
            Circle()
                .fill(bluetooth.bluetoothState == .poweredOn ? Color.primary : Color.secondary)
                .frame(width: 7, height: 7)
            Text(bluetooth.bluetoothStateDescription)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEARBY DEVICES")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(bluetooth.isScanning ? "Stop" : "Scan") {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                }
                .controlSize(.small)
                .disabled(bluetooth.bluetoothState != .poweredOn)
            }

            if bluetooth.devices.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: bluetooth.bluetoothState == .unauthorized ? "lock" : "wave.3.right")
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .padding(.top, 1)
                    Text(bluetooth.scanStatusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            } else {
                Text(bluetooth.scanStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(bluetooth.devices) { device in
                            Button {
                                lightController.connect(to: device)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "wave.3.right")
                                        .font(.system(size: 13))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Text("\(device.rssi) dBm · \(device.id.uuidString.prefix(8))")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    VStack(alignment: .trailing, spacing: 3) {
                                        if bluetooth.connectedDeviceID == device.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .semibold))
                                        } else if bluetooth.connectingDeviceID == device.id {
                                            ProgressView()
                                                .controlSize(.mini)
                                        } else if bluetooth.failedConnectionDeviceID == device.id {
                                            Image(systemName: "exclamationmark")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        Text(bluetooth.connectionStatus(for: device))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(bluetooth.connectedDeviceID == device.id ? Color.primary.opacity(0.07) : .clear)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bluetooth.connectionMessage)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Services and characteristics")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if bluetooth.connectedDeviceID != nil {
                    Button("Disconnect") { lightController.disconnect() }
                        .controlSize(.small)
                }
            }

            if let errorMessage = bluetooth.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            if bluetooth.activePeripheralIdentifier == nil {
                ContentUnavailableView(
                    "No Device Selected",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Select a nearby peripheral to connect and inspect its BLE data.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Peripheral") {
                        inspectionRow("Name", value: bluetooth.activePeripheralName ?? "Name unavailable")
                        inspectionRow("Identifier", value: bluetooth.activePeripheralIdentifier?.uuidString ?? "Unavailable", monospaced: true)
                    }

                    Section("Advertisement") {
                        inspectionRow(
                            "Advertised Services",
                            value: advertisedServicesValue
                        )
                        inspectionRow(
                            "Manufacturer Data (hex)",
                            value: inspectedDevice?.manufacturerDataHex ?? "Not provided",
                            monospaced: true
                        )
                    }

                    Section("Discovered Services") {
                        if bluetooth.services.isEmpty {
                            if bluetooth.isDiscoveringServices {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Discovering services...")
                                }
                            } else {
                                Text("No services discovered.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    ForEach(bluetooth.services) { service in
                        Section {
                            if let discoveryError = service.discoveryError {
                                Text(discoveryError)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            if service.characteristics.isEmpty {
                                Text(service.isDiscoveringCharacteristics ? "Discovering characteristics..." : "No characteristics reported.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(service.characteristics) { characteristic in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(characteristic.id)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text(characteristic.properties.isEmpty ? "No advertised properties" : characteristic.properties.joined(separator: " · "))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)

                                    if let value = characteristic.value {
                                        let valueTitle = characteristic.properties.contains("Notify") || characteristic.properties.contains("Indicate")
                                            ? "Latest Update (hex)"
                                            : "Read Value (hex)"
                                        inspectionRow(valueTitle, value: value, monospaced: true)
                                    } else if characteristic.properties.contains("Read") {
                                        if let readError = characteristic.readError {
                                            inspectionRow("Read Error", value: readError)
                                        } else if characteristic.isReadPending {
                                            Text("Reading characteristic...")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("No value returned.")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if characteristic.properties.contains("Notify") || characteristic.properties.contains("Indicate") {
                                        inspectionRow("Notifications", value: characteristic.notificationStatus)
                                        if let notificationError = characteristic.notificationError {
                                            inspectionRow("Notification Error", value: notificationError)
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        } header: {
                            Text(service.id)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var inspectedDevice: BluetoothDevice? {
        guard let identifier = bluetooth.activePeripheralIdentifier else { return nil }
        return bluetooth.devices.first(where: { $0.id == identifier })
    }

    private var advertisedServicesValue: String {
        guard let serviceUUIDs = inspectedDevice?.advertisedServiceUUIDs, !serviceUUIDs.isEmpty else {
            return "Not provided"
        }
        return serviceUUIDs.joined(separator: "\n")
    }

    private func inspectionRow(_ title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(size: 10, design: .monospaced) : .system(size: 11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum AppSection {
        case glow
        case bluetooth
    }
}