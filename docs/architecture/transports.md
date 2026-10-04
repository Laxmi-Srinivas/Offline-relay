# Transport candidates and limitations

## BLE: first phone-to-phone experiment

A central scans and connects; a peripheral advertises a GATT service. The GATT
client discovers a service and characteristics, writes small framed data, and
receives a response/acknowledgement. Both roles are required: a central-only
Flutter package cannot by itself demonstrate phone-to-phone exchange.

Android exposes these roles through Bluetooth APIs, but advertising support,
permissions, radio state, and device behaviour must be checked at runtime.
Android 12+ scanning, advertising, and connecting use runtime Nearby Devices
permissions. Older OS permissions need separate validation if targeted.

iOS exposes central and peripheral roles through Core Bluetooth. This does not
establish interoperability with any particular Android phone or Flutter plugin.
Foreground behaviour is the initial scope; background discovery/advertising
has additional constraints and is not promised.

Payload capacity is not a universal constant. The experiment should use a
conservative small frame, bounded reassembly, sequential writes, an explicit
application ACK, and finite timeouts. Disconnects must clear incomplete state.
Do not infer delivery from a successful local API invocation.

## LAN: later laptop/shared-network experiment

Use mDNS/Bonjour where appropriate to discover a local endpoint, then choose
TCP or WebSocket for the data channel. This choice is still open. A TCP stream
requires explicit message framing; WebSocket messages still need size limits.
Shared Wi-Fi does not guarantee reachability: multicast filtering, access-point
client isolation, OS permissions, and firewalls can prevent communication.
LAN operation does not imply Internet access or a device-created Wi-Fi network.

## Sources

- [Android BLE overview](https://developer.android.com/develop/connectivity/bluetooth/ble/ble-overview)
- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Android advertiser API](https://developer.android.com/reference/android/bluetooth/le/BluetoothLeAdvertiser)
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Apple background processing constraints](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)

These sources establish available platform APIs, not tested OfflineRelay support.
