//
//  BluetoothManager.swift
//  BaseStation Manager
//
//  Created by Jordan Koch on 11/27/23.
//

import Foundation
import CoreBluetooth

enum DeviceState {
    case off
    case on
    case powering
    case booting
    case identifying
    case unknown
    case error

    init(data: Data) {
        guard let byte = data.first else {
            self = .unknown
            return
        }
        
        switch byte {
            case 0x00:
                self = .off
            case 0x0B:
                self = .on
            case 0x08:
                self = .powering
            case 0x01, 0x09:
                self = .booting
            default:
                print("Unknown device state \(byte)")
                self = .error
        }
    }
}

enum CommandType {
    case power
    case identify
}

protocol BluetoothDelegate:NSObject {
    func updatedBluetoothPermissions()
    func startedScanning()
    func completedScanning()
    func discoveredBasestation(basestation:CBPeripheral)
    func connectedToBasestation(basestation:CBPeripheral)
    func receivedDeviceState(basestation:CBPeripheral, state:DeviceState)
    func didFailToSetDeviceState(basestation:CBPeripheral)
}

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    weak var delegate: BluetoothDelegate?

    private var centralManager: CBCentralManager!
    private var basestations: [CBPeripheral] = []
    var lastKnownStates: [UUID: DeviceState] = [:]

    let powerCharacteristicUUID = CBUUID(string: "00001525-1212-EFDE-1523-785FEABCD124")
    let powerOnCommand: Data = Data([0x01])
    let powerOffCommand: Data = Data([0x00])
    
    let identifyCharacteristicUUID = CBUUID(string: "00008421-1212-EFDE-1523-785FEABCD124")
    let identifyCommand: Data = Data([0x01])
    
    private var statusCheckTimers: [UUID: (timer: Timer, elapsedTime: TimeInterval)] = [:]
    private let statusCheckInterval: TimeInterval = 1
    private let statusCheckTimeout: TimeInterval = 18
    
    var isBluetoothOn: Bool {
        print("BLUETOOTH ON? \(centralManager.state)")
        return centralManager.state == .poweredOn
    }
    
    var isBluetoothEnabled: Bool {
        return centralManager.state != .unauthorized && centralManager.state != .unsupported
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    func startScanning() {
        delegate?.startedScanning()

        for (_, timerData) in statusCheckTimers {
            timerData.timer.invalidate()
        }
        statusCheckTimers.removeAll()
        
        for basestation in basestations {
            centralManager.cancelPeripheralConnection(basestation)
        }
        basestations.removeAll()
        lastKnownStates.removeAll()
        
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.centralManager.stopScan()
            self.stoppedScanning()
            self.delegate?.completedScanning()
        }
    }

    private func stoppedScanning() {
        for basestation in basestations {
            delegate?.discoveredBasestation(basestation: basestation)
            connectToPeripheral(basestation)
        }
    }

    private func connectToPeripheral(_ peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
        peripheral.delegate = self
    }
    
    func startCheckingStatus(of peripheral: CBPeripheral) {
        print("start checking status")
        statusCheckTimers[peripheral.identifier] = (timer: Timer.scheduledTimer(withTimeInterval: statusCheckInterval, repeats: true) { [weak self] timer in
            print("should be checking status")
            self?.checkDeviceStatus(peripheral)
        }, elapsedTime: 0)
    }

    private func checkDeviceStatus(_ peripheral: CBPeripheral) {
        guard var timerData = statusCheckTimers[peripheral.identifier] else { return }

        readPowerState(peripheral: peripheral)

        timerData.elapsedTime += statusCheckInterval

        if timerData.elapsedTime >= statusCheckTimeout {
            timerData.timer.invalidate()
            statusCheckTimers.removeValue(forKey: peripheral.identifier)
            DispatchQueue.main.async {
                self.delegate?.receivedDeviceState(basestation: peripheral, state: .error)
            }
        } else {
            statusCheckTimers[peripheral.identifier] = timerData
        }
    }

    func readPowerState(peripheral: CBPeripheral) {
        guard let services = peripheral.services else {
            print("Services not discovered for the peripheral")
            return
        }

        for service in services {
            if let characteristics = service.characteristics {
                for characteristic in characteristics where characteristic.uuid == powerCharacteristicUUID {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }
    
    func writeToCharacteristic(peripheral: CBPeripheral, type: CommandType, value: Data) {
        guard let services = peripheral.services else { return }
        for service in services {
            guard let characteristics = service.characteristics else { continue }
            for characteristic in characteristics {
                if (type == .power && characteristic.uuid == powerCharacteristicUUID) {
                    print("write power")
                    peripheral.writeValue(value, for: characteristic, type: .withResponse)
                }
                else if (type == .identify && characteristic.uuid == identifyCharacteristicUUID) {
                    print("write identify")
                    peripheral.writeValue(value, for: characteristic, type: .withResponse)
                }
            }
        }
    }
    
    func turnOnDevice(peripheral: CBPeripheral) {
        print("Turning on device")
        writeToCharacteristic(peripheral: peripheral, type: .power, value: powerOnCommand)
        startCheckingStatus(of: peripheral)
    }

    func turnOffDevice(peripheral: CBPeripheral) {
        print("Turning off device")
        invalidateTimer(for: peripheral, withNewState: .unknown)
        writeToCharacteristic(peripheral: peripheral, type: .power, value: powerOffCommand)
    }
    
    func identify(peripheral: CBPeripheral) {
        print("Toggling identify")
        writeToCharacteristic(peripheral: peripheral, type: .identify, value: identifyCommand)
        
        lastKnownStates[peripheral.identifier] = .identifying
        delegate?.receivedDeviceState(basestation: peripheral, state: .identifying)
        
        statusCheckTimers[peripheral.identifier] = (timer: Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            print("Done identifying")
            self?.delegate?.receivedDeviceState(basestation: peripheral, state: .on)
            self?.statusCheckTimers[peripheral.identifier]?.timer.invalidate()
            self?.statusCheckTimers.removeValue(forKey: peripheral.identifier)
        }, elapsedTime: 0)
    }
    
    /* DELEGATE */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.updatedBluetoothPermissions()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        delegate?.connectedToBasestation(basestation: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let name = peripheral.name {
            if (name.contains("LHB-") && !alreadyInArray(basestation: peripheral)) {
                basestations.append(peripheral)
            }
        }
    }
    
    func alreadyInArray(basestation: CBPeripheral) -> Bool {
        return basestations.contains(where: { $0.identifier == basestation.identifier })
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error reading characteristic: \(error.localizedDescription)")
            invalidateTimer(for: peripheral, withNewState: .error)
            return
        }

        guard let value = characteristic.value else {
            print("Invalid or unknown state")
            return
        }

        let newState = DeviceState(data: value)

        if (lastKnownStates[peripheral.identifier] != newState) {
            lastKnownStates[peripheral.identifier] = newState
            delegate?.receivedDeviceState(basestation: peripheral, state: newState)
        }

        if (newState == .on || (statusCheckTimers[peripheral.identifier]?.elapsedTime ?? 0) >= statusCheckTimeout) {
            invalidateTimer(for: peripheral, withNewState: newState)
        }
    }

    private func invalidateTimer(for peripheral: CBPeripheral, withNewState newState: DeviceState) {
        statusCheckTimers[peripheral.identifier]?.timer.invalidate()
        statusCheckTimers.removeValue(forKey: peripheral.identifier)

        delegate?.receivedDeviceState(basestation: peripheral, state: newState)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            print("No services found")
            return
        }

        for service in services {
            peripheral.discoverCharacteristics([], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == powerCharacteristicUUID {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error writing to characteristic: \(error.localizedDescription)")
            self.delegate?.didFailToSetDeviceState(basestation: peripheral)
            return
        }

        print("Successfully wrote to characteristic: \(characteristic.uuid), reading state...")
        if (characteristic.uuid == powerCharacteristicUUID) {
            print("power char, reading state")
            peripheral.readValue(for: characteristic)
        }
    }
    
}
