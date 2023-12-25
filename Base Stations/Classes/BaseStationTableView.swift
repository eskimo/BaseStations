//
//  BasestationTableView.swift
//  Base Station Manager
//
//  Created by Jordan Koch on 11/27/23.
//

import UIKit
import CoreBluetooth

struct Basestation {
    var peripheral: CBPeripheral
    var state: DeviceState
}

enum BasestationAction {
    case turnOn
    case turnOff
    case identify
    case cancel
}

class BasestationTableView: UITableViewController, BluetoothDelegate {
    var bluetoothManager = BluetoothManager()
    var basestations: [Basestation] = []
    
    private let messageLabel = UILabel()
    private var messageLabelCenterYConstraint: NSLayoutConstraint?
    
    private var isScanning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Base Stations"
        
        if refreshControl == nil {
            refreshControl = UIRefreshControl()
        }
        
        refreshControl?.addTarget(self, action: #selector(refreshBasestations(_:)), for: .valueChanged)

        tableView.register(BasestationTableViewCell.self, forCellReuseIdentifier: "BasestationCell")
    
        navigationController?.isToolbarHidden = true
        let flexibleSpaceLeft = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let bulkControlButton = UIBarButtonItem(title: "Bulk Control", style: .plain, target: self, action: #selector(bulkControl))
        let flexibleSpaceRight = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [flexibleSpaceLeft, bulkControlButton, flexibleSpaceRight]
    
        setupScanningIndicatorAndMessageLabel()
        
        bluetoothManager.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        startScanning()
    }
    
    @objc private func bulkControl(sender: UIBarButtonItem) {
        showBulkControlActionSheet(from: sender) { [weak self] action in
            guard let self = self else { return }
            self.performAction(action, on: self.basestations)
        }
    }
    
    private func setupScanningIndicatorAndMessageLabel() {
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(messageLabel)

        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        messageLabelCenterYConstraint = messageLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        
        NSLayoutConstraint.activate([
            messageLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])
    }
    
    func updateMessageLabel() {
        var message:String?
        if (!bluetoothManager.isBluetoothEnabled) {
            message = "Bluetooth on this device isn't supported or permissions were denied."
        }
        else if (isScanning) {
            message = "Scanning for base stations..."
        }
        else if (basestations.isEmpty) {
            message = "No base stations were found."
        }

        if (message != nil) {
            messageLabel.text = message
            messageLabel.isHidden = false
        }
        else {
            messageLabel.isHidden = true
        }
    }
    
    func updatedBluetoothPermissions() {
        if (bluetoothManager.isBluetoothEnabled) {
            startScanning()
        }
        else {
            updateMessageLabel()
        }
    }
    
    @objc private func refreshBasestations(_ sender: Any) {
        startScanning()
    }

    private func startScanning() {
        if (bluetoothManager.isBluetoothEnabled && bluetoothManager.isBluetoothOn) {
            if (isScanning) {
                print("already scanning")
                return
            }
            basestations.removeAll()
            reloadTable()
            bluetoothManager.startScanning()
        }
        else {
            completedScanning()
        }
    }

    func startedScanning() {
        print("Started scanning")
        
        isScanning = true
        refreshControl?.beginRefreshing()
        updateMessageLabel()
        updateBulkControl()
    }
    
    func completedScanning() {
        print("Completed scanning")
        
        isScanning = false
        refreshControl?.endRefreshing()
        updateMessageLabel()
        updateBulkControl()
    }
    
    func updateBulkControl() {
        if (basestations.isEmpty) {
            navigationController?.isToolbarHidden = true
        }
        else {
            var unknown = false
            for basestation in basestations {
                if (basestation.state == .unknown) {
                    unknown = true
                }
            }
            
            if (unknown) {
                navigationController?.isToolbarHidden = true
            }
            else {
                navigationController?.isToolbarHidden = false
            }
        }
    }
    
    func discoveredBasestation(basestation: CBPeripheral) {
        print("Discovered basestation \(basestation.name ?? "Unknown")")

        let newBasestation = Basestation(peripheral: basestation, state: .unknown)
        basestations.append(newBasestation)
        DispatchQueue.main.async {
            self.reloadTable()
            print("reload data for discovered basestations")
        }
    }
    
    func reloadTable() {
        basestations.sort { (basestation1, basestation2) -> Bool in
            guard let name1 = basestation1.peripheral.name, let name2 = basestation2.peripheral.name else {
                return false
            }
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }

        tableView.reloadData()
    }
    
    func connectedToBasestation(basestation: CBPeripheral) {
        print("Connected to basestation \(basestation.name)")
    }
    
    func receivedDeviceState(basestation: CBPeripheral, state: DeviceState) {
        print("Received device state \(basestation.name) - state: \(state)")
        
        bluetoothManager.lastKnownStates[basestation.identifier] = state
        
        if let index = basestations.firstIndex(where: { $0.peripheral.identifier == basestation.identifier }) {
            basestations[index].state = state
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            print("reload row: \(basestation.name)")
        }
        
        updateBulkControl()
    }
    
    func didSetDeviceState(basestation: CBPeripheral, state: DeviceState) {
        print("Set device state \(basestation.name) - state: \(state)")
        
        if let index = basestations.firstIndex(where: { $0.peripheral.identifier == basestation.identifier }) {
            basestations[index].state = state
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            print("reload row: \(basestation.name)")
        }
    }
    
    func didFailToSetDeviceState(basestation: CBPeripheral) {
        print("Failed to set device state \(basestation.name)")
        
        if let index = basestations.firstIndex(where: { $0.peripheral.identifier == basestation.identifier }) {
            basestations[index].state = .error
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            print("reload row: \(basestation.name)")
        }
    }
    
    func showIndividualActionSheet(for basestation: Basestation, sourceView: UIView, completion: @escaping (BasestationAction) -> Void) {
        let actionSheet = UIAlertController(title: basestation.peripheral.name, message: nil, preferredStyle: .actionSheet)

        let actionTitle = basestation.state == .error || basestation.state == .off ? "Turn On" : "Turn Off"
        let action = basestation.state == .error || basestation.state == .off ? BasestationAction.turnOn : BasestationAction.turnOff

        let toggleAction = UIAlertAction(title: actionTitle, style: .default) { _ in
            completion(action)
        }
        let identifyAction = UIAlertAction(title: "Identify", style: .default) { _ in
            completion(.identify)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(.cancel)
        }
        
        if (basestation.state == .on) {
            actionSheet.addAction(identifyAction)
        }
        
        actionSheet.addAction(toggleAction)
        actionSheet.addAction(cancelAction)
        
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = sourceView
            popoverController.sourceRect = sourceView.bounds
        }

        present(actionSheet, animated: true)
    }
    
    func showBulkControlActionSheet(from toolbarItem: UIBarButtonItem, completion: @escaping (BasestationAction) -> Void) {
        let actionSheet = UIAlertController(title: "Bulk Control", message: nil, preferredStyle: .actionSheet)

        let turnOnAction = UIAlertAction(title: "Turn On", style: .default) { _ in
            completion(.turnOn)
        }
        let turnOffAction = UIAlertAction(title: "Turn Off", style: .default) { _ in
            completion(.turnOff)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(.cancel)
        }
        
        actionSheet.addAction(turnOnAction)
        actionSheet.addAction(turnOffAction)
        actionSheet.addAction(cancelAction)
        
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.barButtonItem = toolbarItem
        }
    
        present(actionSheet, animated: true)
    }
    
    func performAction(_ action: BasestationAction, on basestations: [Basestation]) {
        basestations.forEach { basestation in
            switch action {
                case .turnOn:
                    receivedDeviceState(basestation: basestation.peripheral, state: .unknown)
                    bluetoothManager.turnOnDevice(peripheral: basestation.peripheral)

                case .turnOff:
                    receivedDeviceState(basestation: basestation.peripheral, state: .unknown)
                    bluetoothManager.turnOffDevice(peripheral: basestation.peripheral)
                
                case .identify:
                    receivedDeviceState(basestation: basestation.peripheral, state: .identifying)
                    bluetoothManager.identify(peripheral: basestation.peripheral)
                
                default:
                    print("cancel")
                    break
            }
        }
    }
    
    /* TABLE */
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return basestations.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BasestationCell", for: indexPath) as! BasestationTableViewCell
        let basestation = basestations[indexPath.row]
        cell.textLabel?.text = basestation.peripheral.name ?? "Unknown Basestation"
        cell.configureForState(basestation.state)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let basestation = basestations[indexPath.row]
        
        if (basestation.state != .unknown) {
            if let view = tableView.cellForRow(at: indexPath) {
                showIndividualActionSheet(for: basestation, sourceView: view) { [weak self] action in
                    print("selected: \(action)")
                    self?.performAction(action, on: [basestation])
                }
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

}
