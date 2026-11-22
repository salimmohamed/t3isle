import CoreBluetooth
import Foundation
import IOBluetooth
import T3IsleCore

@MainActor
final class T3HeadphonesMonitor: NSObject {
    private let popup: HeadphonesPopup
    private var state = HeadphonesAccess(access: BluetoothAccess(CBManager.authorization))
    private var accessListener: CBCentralManager?
    private let accessQueue = DispatchQueue(label: "dev.t3isle.bluetooth-access")
    private var watchTask: Task<Void, Never>?
    private var connectNotification: IOBluetoothUserNotification?
    private var watchStarted = false
    private let startup = StartupHeadphones()
    private var demoTask: Task<Void, Never>?

    init(popup: HeadphonesPopup) {
        self.popup = popup
    }

    func setEnabled(_ enabled: Bool) {
        state.setEnabled(enabled)
        reconcile()
    }

    func accessChanged(to access: BluetoothAccess) {
        state.accessChanged(to: access)
        reconcile()
    }

    private func reconcile() {
        if T3IsleRuntime.isHeadphonesDemo {
            state.enabled ? startDemo() : stop()
            return
        }
        switch state.watch {
        case .off: stop()
        case .listenForAccess:
            stopWatching()
            listenForAccess()
        case .watch:
            listenForAccess()
            watch()
        }
    }

    private func listenForAccess() {
        guard accessListener == nil else { return }
        accessListener = CBCentralManager(delegate: self, queue: accessQueue,
                                          options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func watch() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            let connected = await Self.connectedAddresses()
            guard !Task.isCancelled, let self else { return }
            startup.begin(alreadyConnected: connected)
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                             selector: #selector(deviceConnected(_:device:)))
            watchStarted = true
        }
    }

    private func startDemo() {
        guard demoTask == nil else { return }
        demoTask = Task { [weak self] in await self?.runDemo() }
    }

    private func stop() {
        stopWatching()
        accessListener = nil
        demoTask?.cancel()
        demoTask = nil
    }

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        startup.end()
        connectNotification?.unregister()
        connectNotification = nil
        watchStarted = false
        popup.dismiss()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        guard startup.isNewConnect(forgetting: address), Self.isAudio(device) else { return }
        let name = device.name ?? "Headphones"
        let classOfDevice = device.classOfDevice
        Task { await announce(address: address, classOfDevice: classOfDevice, fallbackName: name) }
    }

    private func announce(address: String, classOfDevice: UInt32, fallbackName: String) async {
        let first = await Self.report(address: address)
        let name = first?.name ?? fallbackName
        let connect = HeadphonesConnect(address: address, name: name,
                                        kind: HeadphonesKind(appleProductID: first?.appleProductID,
                                                             classOfDevice: classOfDevice, name: name),
                                        battery: first?.battery ?? HeadphonesBattery())
        guard state.watch == .watch else { return }
        popup.show(connect)
        try? await Task.sleep(for: .milliseconds(1500))
        if let fresh = await Self.report(address: address) {
            popup.update(battery: fresh.battery, for: connect.id)
        }
    }

    private func runDemo() async {
        let demo = [
            HeadphonesConnect(address: "demo-pro", name: "AirPods Pro", kind: .airpodsPro,
                              battery: HeadphonesBattery(left: 100, right: 100)),
            HeadphonesConnect(address: "demo-max", name: "AirPods Max", kind: .airpodsMax,
                              battery: HeadphonesBattery(single: 64)),
        ]
        var index = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            let next = demo[index % demo.count]
            popup.show(HeadphonesConnect(address: next.address, name: next.name, kind: next.kind, battery: next.battery))
            index += 1
            try? await Task.sleep(for: .seconds(12))
        }
    }

    private static func isAudio(_ device: IOBluetoothDevice) -> Bool {
        let audioServices: [UInt16] = [0x110B, 0x1108, 0x111E]
        if audioServices.contains(where: { device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: $0)) != nil }) {
            return true
        }
        return BluetoothAudioClass.isAudioVideo(classOfDevice: device.classOfDevice)
    }

    private nonisolated static func connectedAddresses() async -> Set<String> {
        await Task.detached(priority: .utility) {
            let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            return Set(paired.filter { $0.isConnected() }.compactMap(\.addressString))
        }.value
    }

    private nonisolated static func report(address: String) async -> BluetoothReport? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return BluetoothReport.find(address: address, inSystemProfilerJSON: data)
        }.value
    }
}

extension T3HeadphonesMonitor: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in self?.accessChanged(to: BluetoothAccess(CBManager.authorization)) }
    }
}

#if DEBUG
extension T3HeadphonesMonitor {
    var debugState: DebugState.HeadphonesMonitor {
        let status: DebugState.HeadphonesMonitor.Status = watchStarted ? .watching
            : accessListener != nil ? .listening : .off
        return DebugState.HeadphonesMonitor(bluetooth: state.access, status: status)
    }

    var isSettled: Bool {
        watchTask == nil || watchStarted
    }

    var systemAccess: BluetoothAccess {
        BluetoothAccess(CBManager.authorization)
    }
}
#endif
