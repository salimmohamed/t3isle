import Foundation
import IOBluetooth
import T3IsleCore

@MainActor
final class T3HeadphonesMonitor: NSObject {
    private let popup: HeadphonesPopup
    private var connectNotification: IOBluetoothUserNotification?
    private var alreadyConnected: Set<String> = []
    private var demoTask: Task<Void, Never>?

    init(popup: HeadphonesPopup) {
        self.popup = popup
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard connectNotification == nil, demoTask == nil else { return }
        if T3IsleRuntime.isHeadphonesDemo {
            demoTask = Task { [weak self] in await self?.runDemo() }
            return
        }
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        alreadyConnected = Set(paired.filter { $0.isConnected() }.compactMap(\.addressString))
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    private func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        demoTask?.cancel()
        demoTask = nil
        popup.dismiss()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        if alreadyConnected.remove(address) != nil { return }
        guard Self.isAudio(device) else { return }
        let name = device.name ?? "Headphones"
        Task { await announce(address: address, fallbackName: name) }
    }

    private func announce(address: String, fallbackName: String) async {
        let first = await Self.report(address: address)
        let connect = HeadphonesConnect(address: address, name: first?.name ?? fallbackName,
                                        kind: HeadphonesKind(productID: first?.productID, name: fallbackName),
                                        battery: first?.battery ?? HeadphonesBattery())
        popup.show(connect)
        try? await Task.sleep(for: .milliseconds(1500))
        if let fresh = await Self.report(address: address) {
            popup.update(battery: fresh.battery, for: connect.id)
        }
    }

    private func runDemo() async {
        let demo = [
            HeadphonesConnect(address: "demo-pro", name: "AirPods Pro", kind: .airpodsPro,
                              battery: HeadphonesBattery(left: 100, right: 95, chargingCase: 80)),
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
        let audioVideoMajorClass: UInt32 = 0x04
        return (device.classOfDevice >> 8) & 0x1F == audioVideoMajorClass
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
