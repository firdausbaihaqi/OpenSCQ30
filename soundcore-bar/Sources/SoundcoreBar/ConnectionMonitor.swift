import IOBluetooth

/// Reports when the earbuds connect or disconnect, using IOBluetooth notifications instead of polling.
@MainActor
final class ConnectionMonitor: NSObject {
    private var device: IOBluetoothDevice?
    private var onChange: ((Bool) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?

    /// Calls `onChange` immediately with the current state, then on every change.
    func watch(mac: String, onChange: @escaping (Bool) -> Void) {
        guard device == nil, let device = IOBluetoothDevice(addressString: mac) else { return }
        self.device = device
        self.onChange = onChange
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(didConnect(_:device:))
        )
        if device.isConnected() { watchDisconnect() }
        onChange(device.isConnected())
    }

    @objc private func didConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.addressString == self.device?.addressString else { return }
        watchDisconnect()
        onChange?(true)
    }

    @objc private func didDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        disconnectNotification?.unregister()
        disconnectNotification = nil
        onChange?(false)
    }

    // Disconnect notifications are per connection, so re-register after every connect.
    private func watchDisconnect() {
        disconnectNotification?.unregister()
        disconnectNotification = device?.register(
            forDisconnectNotification: self, selector: #selector(didDisconnect(_:device:))
        )
    }
}
