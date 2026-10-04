import 'dart:async';

import 'package:flutter/services.dart';
import 'package:relay_transport/relay_transport.dart';

import 'helper_availability.dart';

/// Flutter bridge for the Android GATT transport in the host application.
/// The method/event channel names are private to this app.
final class BleRelayTransport
    implements RelayTransport, HelperAvailabilityControl {
  static const _methods = MethodChannel('dev.offlinerelay/ble/methods');
  static const _events = EventChannel('dev.offlinerelay/ble/events');

  final _incoming = StreamController<RelayConnection>.broadcast();
  final _availabilityStates =
      StreamController<HelperAvailabilityState>.broadcast();
  final _acceptedConnections =
      StreamController<HelperAcceptedEvent>.broadcast();
  final _discoveries = <StreamController<RelayPeer>>{};
  final _connections = <String, _BleRelayConnection>{};
  final _helperConnectionIds = <String>{};
  late final StreamSubscription<Object?> _eventSubscription;
  bool _disposed = false;
  bool _scanning = false;

  BleRelayTransport() {
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onEventError,
    );
  }

  @override
  Stream<RelayConnection> get incomingConnections => _incoming.stream;

  @override
  Stream<HelperAvailabilityState> get availabilityStates =>
      _availabilityStates.stream;

  @override
  Stream<HelperAcceptedEvent> get acceptedConnections =>
      _acceptedConnections.stream;

  @override
  Stream<RelayPeer> discover() {
    late final StreamController<RelayPeer> controller;
    controller = StreamController<RelayPeer>(
      onListen: () async {
        _ensureOpen();
        _discoveries.add(controller);
        if (!_scanning) {
          _scanning = true;
          try {
            await _methods.invokeMethod<void>('startDiscovery');
          } catch (error, stack) {
            _scanning = false;
            if (!controller.isClosed) controller.addError(error, stack);
          }
        }
      },
      onCancel: () async {
        _discoveries.remove(controller);
        if (_discoveries.isEmpty && _scanning && !_disposed) {
          _scanning = false;
          await _methods.invokeMethod<void>('stopDiscovery');
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<RelayConnection> connect(RelayPeer peer) async {
    _ensureOpen();
    final result = await _methods.invokeMapMethod<String, Object?>('connect', {
      'peerId': peer.id,
    });
    if (result == null) throw StateError('Native connect returned no session');
    final connection = _connectionFrom(
      result['connectionId'],
      result['peer'],
      fallback: peer,
    );
    return connection;
  }

  @override
  Future<void> advertise(RelayProfile profile) async {
    _ensureOpen();
    await _methods.invokeMethod<void>('advertise', {
      'profile': {
        'id': profile.id,
        'label': profile.label,
        'metadata': profile.metadata,
      },
    });
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_disposed) await _methods.invokeMethod<void>('stopAdvertising');
  }

  @override
  Future<void> stopHelperAvailability() async {
    if (!_disposed) await _methods.invokeMethod<void>('stopHelper');
  }

  void _onEvent(Object? raw) {
    if (raw is! Map<Object?, Object?>) return;
    final event = Map<String, Object?>.from(raw);
    switch (event['event']) {
      case 'peerDiscovered':
        final peer = _peerFrom(event['peer']);
        for (final controller in List.of(_discoveries)) {
          if (!controller.isClosed) controller.add(peer);
        }
        break;
      case 'incomingConnection':
        final id = event['connectionId'];
        if (id is String) _helperConnectionIds.add(id);
        if (id is String && _connections.containsKey(id)) break;
        final connection = _connectionFrom(id, event['peer']);
        _incoming.add(connection);
        break;
      case 'helperState':
        _availabilityStates.add(
          HelperAvailabilityState(
            enabled: event['enabled'] == true,
            displayName: event['displayName'] as String?,
          ),
        );
        break;
      case 'helperAccepted':
        final id = event['connectionId'];
        if (id is String &&
            _helperConnectionIds.contains(id) &&
            _connections.containsKey(id)) {
          _acceptedConnections.add(
            HelperAcceptedEvent(
              connectionId: id,
              requestId: event['requestId'] as String?,
              peerName: event['peerName'] as String? ?? 'Nearby user',
              connection: _connections[id],
            ),
          );
        }
        break;
      case 'message':
        final id = event['connectionId'];
        final bytes = event['message'];
        if (id is String && bytes is Uint8List) {
          _connections[id]?._addMessage(bytes);
        }
        break;
      case 'helperSnapshot':
        final activeId = event['connectionId'];
        for (final id in List.of(_helperConnectionIds)) {
          if (id == activeId) continue;
          _helperConnectionIds.remove(id);
          _connections.remove(id)?._finish('Helper conversation ended.');
        }
        break;
      case 'disconnected':
        final id = event['connectionId'];
        if (id is String) {
          _helperConnectionIds.remove(id);
          _connections
              .remove(id)
              ?._finish(event['reason']?.toString() ?? 'Disconnected');
        }
        break;
      case 'error':
        _scanning = false;
        final error = StateError(event['message']?.toString() ?? 'BLE error');
        for (final controller in List.of(_discoveries)) {
          if (!controller.isClosed) controller.addError(error);
        }
        _incoming.addError(error);
        break;
      case 'sessionEnded':
        _scanning = false;
        for (final controller in List.of(_discoveries)) {
          if (!controller.isClosed) {
            controller.addError(
              StateError(
                event['reason']?.toString() ?? 'Search stopped. Try again.',
              ),
            );
          }
        }
        break;
    }
  }

  void _onEventError(Object error, StackTrace stack) {
    for (final controller in List.of(_discoveries)) {
      if (!controller.isClosed) controller.addError(error, stack);
    }
    if (!_disposed) _incoming.addError(error, stack);
  }

  _BleRelayConnection _connectionFrom(
    Object? rawId,
    Object? rawPeer, {
    RelayPeer? fallback,
  }) {
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Missing native connection ID');
    }
    final connection = _connections.putIfAbsent(rawId, () {
      final peer = rawPeer == null && fallback != null
          ? fallback
          : _peerFrom(rawPeer);
      return _BleRelayConnection(rawId, peer, _methods, () {
        _connections.remove(rawId);
        _helperConnectionIds.remove(rawId);
      });
    });
    return connection;
  }

  RelayPeer _peerFrom(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const FormatException('Malformed native peer');
    }
    final map = Map<String, Object?>.from(raw);
    final metadata = map['metadata'];
    return RelayPeer(
      id: map['id'] as String,
      label: map['label'] as String? ?? 'Nearby user',
      metadata: metadata is Map
          ? metadata.map((key, value) => MapEntry('$key', '$value'))
          : const {},
    );
  }

  void _ensureOpen() {
    if (_disposed) throw StateError('Transport has been disposed');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSubscription.cancel();
    // Disposing a Flutter engine must not close service-owned helper availability.
    // Native dispose releases Activity-owned links; helper state is restored on attach.
    for (final connection in List.of(_connections.values)) {
      await connection._detach();
    }
    _connections.clear();
    _helperConnectionIds.clear();
    try {
      await _methods.invokeMethod<void>('dispose');
    } finally {
      await _incoming.close();
      await _availabilityStates.close();
      await _acceptedConnections.close();
      for (final controller in List.of(_discoveries)) {
        await controller.close();
      }
      _discoveries.clear();
    }
  }
}

final class _BleRelayConnection implements RelayConnection {
  _BleRelayConnection(this._id, this.peer, this._methods, this._onClose);

  final String _id;
  final MethodChannel _methods;
  final void Function() _onClose;
  final _messages = StreamController<Uint8List>.broadcast();
  bool _closed = false;

  @override
  final RelayPeer peer;

  @override
  int get maxMessageBytes => relayMaxMessageBytes;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('Connection is closed');
    if (message.isEmpty || message.length > maxMessageBytes) {
      throw ArgumentError('Message must be 1..$maxMessageBytes bytes');
    }
    await _methods.invokeMethod<void>('send', {
      'connectionId': _id,
      'message': message,
    });
  }

  void _addMessage(Uint8List message) {
    if (!_closed) _messages.add(message);
  }

  void _finish(String reason) {
    if (_closed) return;
    _closed = true;
    _messages.addError(StateError(reason));
    _messages.close();
    _onClose();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _onClose();
    try {
      await _methods.invokeMethod<void>('close', {'connectionId': _id});
    } finally {
      await _messages.close();
    }
  }

  Future<void> _detach() async {
    _closed = true;
    await _messages.close();
  }
}
