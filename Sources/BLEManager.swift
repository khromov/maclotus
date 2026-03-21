import Foundation
import CoreBluetooth
import SwiftUI

enum ConnectionStatus {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
}

class BLEManager: NSObject, ObservableObject {
    // MARK: - Published state

    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var discoveredPeripherals: [DiscoveredPeripheral] = []

    // Lamp state (write-only protocol; tracked locally)
    @Published var isPoweredOn: Bool = true
    @Published var currentColor: Color = .white
    @Published var brightness: Double = 100
    @Published var activeEffectID: UInt8? = nil
    @Published var effectSpeed: Double = 50
    @Published var isBreathing: Bool = false
    @Published var breatheCycleDuration: Double = 4.0
    @Published var breatheColor: Color? = nil

    var connectedPeripheralName: String? {
        connectedPeripheral?.name ?? "Unknown"
    }

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withoutResponse

    private var pendingColorWork: DispatchWorkItem?
    private var pendingBrightnessWork: DispatchWorkItem?
    private var pendingSpeedWork: DispatchWorkItem?
    private var breatheTimer: Timer?
    private var breatheStartTime: Date?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredPeripherals = []
        connectionStatus = .scanning
        // Scan for all devices (mirrors acceptAllDevices in web app)
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionStatus {
            connectionStatus = .disconnected
        }
    }

    func connect(to discovered: DiscoveredPeripheral) {
        stopScanning()
        connectionStatus = .connecting
        connectedPeripheral = discovered.peripheral
        centralManager.connect(discovered.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func sendPowerOn() {
        isPoweredOn = true
        sendCommand(LampCommand.powerOn)
    }

    func sendPowerOff() {
        stopBreathing()
        isPoweredOn = false
        sendCommand(LampCommand.powerOff)
    }

    func startBreathing() {
        activeEffectID = nil
        if let color = breatheColor {
            let (r, g, b) = color.rgbComponents
            sendCommand(LampCommand.setColor(r: r, g: g, b: b))
        }
        breatheStartTime = Date()
        let cycleDuration = breatheCycleDuration
        breatheTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.breatheStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            let phase = (elapsed / cycleDuration) * 2 * Double.pi
            let normalized = (sin(phase - Double.pi / 2) + 1) / 2
            let brightnessValue = 1.0 + normalized * 99.0
            self.brightness = brightnessValue
            self.sendCommand(LampCommand.setBrightness(Int(brightnessValue)))
        }
        isBreathing = true
    }

    func stopBreathing() {
        breatheTimer?.invalidate()
        breatheTimer = nil
        isBreathing = false
    }

    func sendColor(_ color: Color) {
        stopBreathing()
        if !isPoweredOn {
            isPoweredOn = true
            sendCommand(LampCommand.powerOn)
        }
        currentColor = color
        activeEffectID = nil
        let (r, g, b) = color.rgbComponents
        pendingColorWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.sendCommand(LampCommand.setColor(r: r, g: g, b: b))
        }
        pendingColorWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func sendBrightness(_ value: Double) {
        stopBreathing()
        brightness = value
        pendingBrightnessWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.sendCommand(LampCommand.setBrightness(Int(value)))
        }
        pendingBrightnessWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func sendEffect(_ mode: UInt8) {
        stopBreathing()
        activeEffectID = mode
        sendCommand(LampCommand.setEffect(mode: mode))
    }

    func sendEffectSpeed(_ value: Double) {
        effectSpeed = value
        pendingSpeedWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.sendCommand(LampCommand.setEffectSpeed(Int(value)))
        }
        pendingSpeedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    // MARK: - Internal

    func sendCommand(_ data: Data) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral,
              peripheral.state == .connected else { return }
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }

    private func attemptAutoReconnect() {
        guard let uuidString = UserDefaults.standard.string(forKey: BLEConstants.lastPeripheralUUIDKey),
              let uuid = UUID(uuidString: uuidString) else { return }

        // Try to find already-connected peripheral first
        let connected = centralManager.retrieveConnectedPeripherals(withServices: BLEConstants.serviceUUIDs)
        if let peripheral = connected.first(where: { $0.identifier == uuid }) {
            connectedPeripheral = peripheral
            connectionStatus = .connecting
            centralManager.connect(peripheral, options: nil)
            return
        }

        // Try to retrieve by identifier
        let known = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = known.first {
            connectedPeripheral = peripheral
            connectionStatus = .connecting
            centralManager.connect(peripheral, options: nil)
        }
    }

    /// Select the best writable characteristic from all discovered services.
    /// Mirrors the logic in bluetooth.js findServiceAndCharacteristic().
    private func selectCharacteristic(from peripheral: CBPeripheral) -> (CBCharacteristic, CBCharacteristicWriteType)? {
        guard let services = peripheral.services else { return nil }

        var candidates: [CBCharacteristic] = []

        for service in services {
            // Skip standard BLE services
            let uuidLower = service.uuid.uuidString.lowercased()
            let isStandard = BLEConstants.standardServicePrefixes.contains(where: { uuidLower.hasPrefix($0) })
            if isStandard { continue }

            guard let characteristics = service.characteristics else { continue }
            for char in characteristics {
                let props = char.properties
                if props.contains(.write) || props.contains(.writeWithoutResponse) {
                    candidates.append(char)
                }
            }
        }

        if candidates.isEmpty { return nil }

        // Prefer characteristics whose UUID contains "fff" or "ffe"
        let preferred = candidates.first(where: { char in
            let uuidLower = char.uuid.uuidString.lowercased()
            return BLEConstants.preferredUUIDSubstrings.contains(where: { uuidLower.contains($0) })
        }) ?? candidates.first!

        let writeType: CBCharacteristicWriteType = preferred.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse

        return (preferred, writeType)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            attemptAutoReconnect()
        } else {
            connectionStatus = .disconnected
            writeCharacteristic = nil
            connectedPeripheral = nil
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let id = peripheral.identifier

        if let idx = discoveredPeripherals.firstIndex(where: { $0.id == id }) {
            discoveredPeripherals[idx].rssi = RSSI.intValue
        } else {
            discoveredPeripherals.append(DiscoveredPeripheral(
                id: id,
                peripheral: peripheral,
                name: name,
                rssi: RSSI.intValue
            ))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .error(error?.localizedDescription ?? "Failed to connect")
        connectedPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        stopBreathing()
        writeCharacteristic = nil
        connectedPeripheral = nil
        connectionStatus = .disconnected
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        // Wait until all services have their characteristics before selecting
        guard let services = peripheral.services else { return }
        let allDone = services.allSatisfy { $0.characteristics != nil }
        guard allDone else { return }

        if let (char, type) = selectCharacteristic(from: peripheral) {
            writeCharacteristic = char
            writeType = type
            connectionStatus = .connected

            // Save peripheral UUID for auto-reconnect (UserDefaults for GUI, file for CLI)
            let uuidString = peripheral.identifier.uuidString
            UserDefaults.standard.set(uuidString, forKey: BLEConstants.lastPeripheralUUIDKey)
            try? uuidString.write(to: BLEConstants.deviceUUIDFileURL, atomically: true, encoding: .utf8)

            // Send initialization command
            sendCommand(LampCommand.initialize)
        } else {
            connectionStatus = .error("No writable characteristic found")
        }
    }
}

// MARK: - Color helper

private extension Color {
    var rgbComponents: (r: UInt8, g: UInt8, b: UInt8) {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = UInt8(max(0, min(255, Int(nsColor.redComponent * 255))))
        let g = UInt8(max(0, min(255, Int(nsColor.greenComponent * 255))))
        let b = UInt8(max(0, min(255, Int(nsColor.blueComponent * 255))))
        return (r, g, b)
    }
}
