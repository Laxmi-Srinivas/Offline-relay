import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:relay_transport/relay_transport.dart';

import 'transport/helper_availability.dart';

enum RelayUserRole { offlineUser, internetHelper }

class RelayConversationMessage {
  const RelayConversationMessage({
    required this.id,
    required this.text,
    required this.fromLocalUser,
  });

  final String id;
  final String text;
  final bool fromLocalUser;
}

/// Minimal in-memory app flow layered over the platform transport contract.
class _OutgoingRequest {
  _OutgoingRequest(this.peer, this.request);
  final RelayPeer peer;
  final RelayEnvelope request;
  RelayConnection? connection;
  StreamSubscription<Uint8List>? subscription;
}

class RelayDemoController extends ChangeNotifier {
  RelayDemoController(
    this._transport, {
    this.discoveryDuration = const Duration(seconds: 12),
  }) {
    _incomingSubscription = _transport.incomingConnections.listen(
      _onIncomingConnection,
      onError: (Object error) => _setStatus('Connection error: $error'),
    );
    final helperControl = _transport is HelperAvailabilityControl
        ? _transport as HelperAvailabilityControl
        : null;
    if (helperControl != null) {
      _availabilitySubscription = helperControl.availabilityStates.listen(
        _onHelperAvailability,
      );
      _acceptedSubscription = helperControl.acceptedConnections.listen(
        _onHelperAccepted,
      );
    }
  }

  final RelayTransport _transport;
  final Duration discoveryDuration;
  Timer? _discoveryTimer;
  bool isSearchComplete = false;
  String? errorMessage;
  bool get noPeopleFound =>
      isSearchComplete && peers.isEmpty && errorMessage == null;
  final peers = <RelayPeer>[];
  final messages = <RelayConversationMessage>[];

  String displayName = '';
  RelayUserRole role = RelayUserRole.offlineUser;
  String status = 'Choose your name and role to begin.';
  String? remoteName;
  String? incomingPeerName;
  String? incomingRequestId;
  bool isDiscovering = false;
  bool isOffering = false;
  final _outgoing = <String, _OutgoingRequest>{};
  bool _disposed = false;
  bool get isConnecting =>
      _outgoing.values.any((request) => request.connection == null);
  bool get isWaitingForAcceptance => _outgoing.isNotEmpty;
  bool isRequesting(RelayPeer peer) => _outgoing.containsKey(peer.id);
  String? _selectedPeerId;
  String? get selectedPeerId => _selectedPeerId;
  bool inChat = false;

  RelayConnection? _connection;
  RelayConnection? _incomingConnection;
  StreamSubscription<RelayConnection>? _incomingSubscription;
  StreamSubscription<HelperAvailabilityState>? _availabilitySubscription;
  StreamSubscription<HelperAcceptedEvent>? _acceptedSubscription;
  StreamSubscription<RelayPeer>? _discoverySubscription;
  StreamSubscription<Uint8List>? _messageSubscription;

  bool get hasIncomingRequest =>
      _incomingConnection != null && incomingRequestId != null;

  RelayProfile get localProfile => RelayProfile(
    id: 'local-${DateTime.now().microsecondsSinceEpoch}',
    label: _cleanName(displayName),
    metadata: {'role': _roleWireName(role)},
  );

  void updateProfile({required String name, required RelayUserRole role}) {
    displayName = name.trim();
    this.role = role;
    notifyListeners();
  }

  Future<void> findNearbyHelpers() async {
    _requireName();
    if (role != RelayUserRole.offlineUser) {
      throw StateError('Choose Offline User to find helpers.');
    }
    await _discoverySubscription?.cancel();
    _discoveryTimer?.cancel();
    isSearchComplete = false;
    errorMessage = null;
    peers.clear();
    isOffering = false;
    isDiscovering = true;
    status = 'Looking for nearby Internet Helpers…';
    notifyListeners();
    _discoverySubscription = _transport.discover().listen(
      (peer) {
        if (peer.metadata['role'] != 'internet_helper') return;
        if (peers.every((existing) => existing.id != peer.id)) {
          peers.add(peer);
          notifyListeners();
        }
      },
      onError: (Object error) {
        _discoveryTimer?.cancel();
        isDiscovering = false;
        isSearchComplete = true;
        errorMessage = _friendlyError(error);
        _setStatus('Discovery stopped: $error');
      },
    );
    _discoveryTimer = Timer(discoveryDuration, () {
      if (_disposed || !isDiscovering) return;
      // Complete the UI search without cancelling pending native connects.
      if (_outgoing.isNotEmpty) return;
      isDiscovering = false;
      isSearchComplete = true;
      status = peers.isEmpty
          ? 'No one found nearby.'
          : '${peers.length} nearby helpers found.';
      unawaited(_discoverySubscription?.cancel());
      _discoverySubscription = null;
      notifyListeners();
    });
  }

  Future<void> offerHelp() async {
    _requireName();
    if (role != RelayUserRole.internetHelper) {
      throw StateError('Choose Internet Helper to offer help.');
    }
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    _discoveryTimer?.cancel();
    isDiscovering = false;
    isSearchComplete = false;
    errorMessage = null;
    peers.clear();
    await _transport.advertise(localProfile);
    isOffering = true;
    status = 'Help Others is on. You can leave OfflineRelay running.';
    notifyListeners();
  }

  Future<void> stopOfferingHelp() async {
    final helperControl = _transport is HelperAvailabilityControl
        ? _transport as HelperAvailabilityControl
        : null;
    if (helperControl != null) {
      await helperControl.stopHelperAvailability();
    } else {
      await _transport.stopAdvertising();
    }
    isOffering = false;
    status = 'Help Others is off.';
    notifyListeners();
  }

  Future<void> connectTo(RelayPeer peer) async {
    _requireName();
    if (_disposed ||
        inChat ||
        role != RelayUserRole.offlineUser ||
        isRequesting(peer)) {
      return;
    }
    _discoveryTimer?.cancel();
    errorMessage = null;
    final pending = _OutgoingRequest(
      peer,
      RelayEnvelope.create(
        type: RelayMessageType.connectionRequest,
        body: {'name': _cleanName(displayName), 'role': 'offline_user'},
      ),
    );
    _outgoing[peer.id] = pending;
    status = 'Connecting to ${peer.label}…';
    notifyListeners();
    try {
      final connection = await _transport.connect(peer);
      if (_disposed || !identical(_outgoing[peer.id], pending)) {
        await connection.close();
        return;
      }
      pending.connection = connection;
      pending.subscription = connection.messages.listen(
        (bytes) => _onEnvelope(connection, bytes),
        onError: (Object error) => _endOutgoing(
          pending,
          'Connection ended with ${peer.label}: $error',
        ),
        onDone: () =>
            _endOutgoing(pending, 'Connection closed with ${peer.label}.'),
      );
      status = 'Connection request sent to ${peer.label}.';
      notifyListeners();
      await connection.send(pending.request.encode());
    } catch (error) {
      // A cancelled or losing request must never overwrite the winner's state.
      if (!_disposed && identical(_outgoing[peer.id], pending)) {
        errorMessage = _friendlyError(error);
        _endOutgoing(pending, 'Could not connect to ${peer.label}: $error');
      }
    }
  }

  void _endOutgoing(_OutgoingRequest pending, String message) {
    if (_disposed) return;
    final connection = pending.connection;
    if (connection != null && identical(_connection, connection)) {
      if (_releaseEndedConnection(connection)) _setStatus(message);
      return;
    }
    if (!identical(_outgoing[pending.peer.id], pending)) return;
    _outgoing.remove(pending.peer.id);
    unawaited(_closeOutgoing(pending));
    _setStatus(message);
  }

  Future<void> _closeOutgoing(_OutgoingRequest pending) async {
    await pending.subscription?.cancel();
    try {
      await pending.connection?.close();
    } catch (_) {
      /* already ended */
    }
  }

  void _selectWinner(_OutgoingRequest winner) {
    // No await before claiming the winner and invalidating every losing request.
    // Dart stream callbacks execute serially on this isolate.
    if (inChat || !identical(_outgoing[winner.peer.id], winner)) return;
    final losers = _outgoing.values
        .where((request) => !identical(request, winner))
        .toList();
    _outgoing.clear();
    _discoveryTimer?.cancel();
    errorMessage = null;
    _connection = winner.connection;
    _selectedPeerId = winner.peer.id;
    _messageSubscription = winner.subscription;
    remoteName = winner.peer.label;
    inChat = true;
    status = 'Connection accepted by $remoteName.';
    final discovery = _discoverySubscription;
    _discoverySubscription = null;
    isDiscovering = false;
    unawaited(discovery?.cancel());
    for (final loser in losers) {
      unawaited(_closeOutgoing(loser));
    }
    notifyListeners();
  }

  Future<void> acceptIncomingRequest() async {
    final connection = _incomingConnection;
    final requestId = incomingRequestId;
    if (connection == null || requestId == null) {
      throw StateError('There is no connection request to accept.');
    }
    _connection = connection;
    remoteName = incomingPeerName ?? connection.peer.label;
    incomingPeerName = null;
    incomingRequestId = null;
    _incomingConnection = null;
    await _transport.stopAdvertising();
    isOffering = false;
    await _sendEnvelope(
      RelayEnvelope.create(
        type: RelayMessageType.connectionAccept,
        body: {'requestId': requestId},
      ),
    );
    inChat = true;
    status = 'Connected with $remoteName.';
    notifyListeners();
  }

  Future<void> rejectIncomingRequest() async {
    final connection = _incomingConnection;
    final requestId = incomingRequestId;
    if (connection == null || requestId == null) return;
    await connection.send(
      RelayEnvelope.create(
        type: RelayMessageType.connectionReject,
        body: {'requestId': requestId},
      ).encode(),
    );
    _clearIncomingRequest();
    _incomingConnection = null;
    await connection.close();
    isOffering = role == RelayUserRole.internetHelper;
    status = isOffering
        ? 'Connection declined. You are still offering help.'
        : 'Connection declined.';
    notifyListeners();
  }

  Future<void> sendChat(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    final envelope = RelayEnvelope.create(
      type: RelayMessageType.chat,
      body: {'text': value},
    );
    await _sendEnvelope(envelope);
    messages.add(
      RelayConversationMessage(
        id: envelope.id,
        text: value,
        fromLocalUser: true,
      ),
    );
    notifyListeners();
  }

  Future<void> returnToNearby() async {
    _discoveryTimer?.cancel();
    isSearchComplete = false;
    errorMessage = null;
    final pending = _outgoing.values.toList();
    _outgoing.clear();
    inChat = false;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    await Future.wait(pending.map(_closeOutgoing));
    final connection = _connection ?? _incomingConnection;
    _connection = null;
    _incomingConnection = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    if (connection != null) await connection.close();
    await _transport.stopAdvertising();
    final helperControl = _transport is HelperAvailabilityControl
        ? _transport as HelperAvailabilityControl
        : null;
    if (role == RelayUserRole.internetHelper && helperControl != null) {
      await helperControl.stopHelperAvailability();
    }
    peers.clear();
    messages.clear();
    _clearIncomingRequest();
    remoteName = null;
    _selectedPeerId = null;
    isDiscovering = false;
    isOffering = false;
    inChat = false;
    status = 'Choose Find Nearby Helpers or Offer Help.';
    notifyListeners();
  }

  void _onIncomingConnection(RelayConnection connection) {
    if (role != RelayUserRole.internetHelper ||
        _incomingConnection != null ||
        _connection != null) {
      unawaited(connection.close());
      return;
    }
    _incomingConnection = connection;
    incomingPeerName = connection.peer.label;
    _listenForMessages(connection);
    status = 'A nearby user wants to connect.';
    notifyListeners();
  }

  void _onHelperAvailability(HelperAvailabilityState state) {
    role = RelayUserRole.internetHelper;
    if (state.displayName != null && state.displayName!.isNotEmpty) {
      displayName = state.displayName!;
    }
    isOffering = state.enabled;
    if (!inChat && !hasIncomingRequest) {
      status = state.enabled
          ? 'Help Others is on. You can leave OfflineRelay running.'
          : 'Help Others is off.';
    }
    notifyListeners();
  }

  void _onHelperAccepted(HelperAcceptedEvent event) {
    final pending = _incomingConnection;
    if (pending != null) {
      _connection = pending;
      _incomingConnection = null;
    }
    remoteName = event.peerName;
    incomingPeerName = null;
    incomingRequestId = null;
    isOffering = false;
    inChat = true;
    status = 'Connected with $remoteName.';
    notifyListeners();
  }

  void _listenForMessages(RelayConnection connection) {
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = connection.messages.listen(
      (bytes) => _onEnvelope(connection, bytes),
      onError: (Object error) {
        if (!_releaseEndedConnection(connection)) return;
        _setStatus('Connection ended: $error');
      },
      onDone: () {
        if (_releaseEndedConnection(connection)) {
          _setStatus('Connection closed.');
        }
      },
    );
  }

  // A closed helper link must not block the next availability request. Ignore
  // late callbacks from a superseded connection so they cannot clear a new one.
  bool _releaseEndedConnection(RelayConnection connection) {
    final current = identical(_connection, connection);
    final incoming = identical(_incomingConnection, connection);
    if (!current && !incoming) return false;
    if (current) {
      _connection = null;
      _selectedPeerId = null;
    }
    if (incoming) _incomingConnection = null;
    _clearIncomingRequest();
    inChat = false;
    return true;
  }

  void _onEnvelope(RelayConnection connection, Uint8List bytes) {
    if (_disposed) return;
    _OutgoingRequest? pending;
    for (final request in _outgoing.values) {
      if (identical(request.connection, connection)) {
        pending = request;
        break;
      }
    }
    if (pending == null &&
        !identical(_connection, connection) &&
        !identical(_incomingConnection, connection)) {
      return;
    }
    late final RelayEnvelope envelope;
    try {
      envelope = RelayEnvelope.decode(bytes);
    } catch (error) {
      _setStatus('Could not read message: $error');
      return;
    }
    switch (envelope.type) {
      case RelayMessageType.connectionRequest:
        if (role != RelayUserRole.internetHelper ||
            !identical(_incomingConnection, connection)) {
          return;
        }
        incomingRequestId = envelope.id;
        incomingPeerName =
            _bodyString(envelope, 'name') ?? connection.peer.label;
        status = 'Connection request from $incomingPeerName.';
        notifyListeners();
      case RelayMessageType.connectionAccept:
        if (pending == null ||
            envelope.body['requestId'] != pending.request.id) {
          return;
        }
        _selectWinner(pending);
      case RelayMessageType.connectionReject:
        if (pending == null ||
            envelope.body['requestId'] != pending.request.id) {
          return;
        }
        _endOutgoing(
          pending,
          '${pending.peer.label} declined the connection request.',
        );
      case RelayMessageType.chat:
        if (!inChat || !identical(_connection, connection)) return;
        final text = _bodyString(envelope, 'text');
        if (text == null) return;
        messages.add(
          RelayConversationMessage(
            id: envelope.id,
            text: text,
            fromLocalUser: false,
          ),
        );
        notifyListeners();
      case RelayMessageType.serviceRequest:
      case RelayMessageType.serviceResponse:
      // Reserved by the shared transport contract; this MVP treats them as
      // unsupported messages and keeps the chat flow text-only.
    }
  }

  Future<void> _sendEnvelope(RelayEnvelope envelope) async {
    final connection = _connection;
    if (connection == null) throw StateError('Connect first.');
    await connection.send(envelope.encode());
  }

  String? _bodyString(RelayEnvelope envelope, String key) {
    final value = envelope.body[key];
    return value is String ? value : null;
  }

  void _requireName() {
    if (displayName.trim().isEmpty) {
      throw StateError('Enter your name first.');
    }
  }

  String _cleanName(String value) =>
      value.trim().isEmpty ? 'Nearby user' : value.trim();

  String _roleWireName(RelayUserRole value) => switch (value) {
    RelayUserRole.offlineUser => 'offline_user',
    RelayUserRole.internetHelper => 'internet_helper',
  };

  void _clearIncomingRequest() {
    incomingPeerName = null;
    incomingRequestId = null;
  }

  void reportError(Object error) {
    errorMessage = _friendlyError(error);
    _setStatus(errorMessage!);
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Bad state: ', '');
    if (value.toLowerCase().contains('permission')) {
      return 'Nearby permissions are needed to find and connect with helpers.';
    }
    if (value.toLowerCase().contains('bluetooth')) {
      return 'Turn on Bluetooth to find and connect with nearby helpers.';
    }
    return value;
  }

  void _setStatus(String value) {
    status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _disposed = true;
    final pending = _outgoing.values.toList();
    _outgoing.clear();
    for (final request in pending) {
      unawaited(_closeOutgoing(request));
    }
    unawaited(_incomingSubscription?.cancel());
    unawaited(_availabilitySubscription?.cancel());
    unawaited(_acceptedSubscription?.cancel());
    unawaited(_discoverySubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_transport.dispose());
    super.dispose();
  }
}
