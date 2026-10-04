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
class RelayDemoController extends ChangeNotifier {
  RelayDemoController(this._transport) {
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
  bool isConnecting = false;
  bool isWaitingForAcceptance = false;
  bool inChat = false;

  RelayConnection? _connection;
  RelayConnection? _incomingConnection;
  String? _outgoingRequestId;
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
        isDiscovering = false;
        _setStatus('Discovery stopped: $error');
      },
    );
  }

  Future<void> offerHelp() async {
    _requireName();
    if (role != RelayUserRole.internetHelper) {
      throw StateError('Choose Internet Helper to offer help.');
    }
    await _discoverySubscription?.cancel();
    isDiscovering = false;
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
    isConnecting = true;
    status = 'Connecting to ${peer.label}…';
    notifyListeners();
    try {
      final connection = await _transport.connect(peer);
      _connection = connection;
      remoteName = peer.label;
      _listenForMessages(connection);
      await _discoverySubscription?.cancel();
      _discoverySubscription = null;
      isDiscovering = false;
      final request = RelayEnvelope.create(
        type: RelayMessageType.connectionRequest,
        body: {'name': _cleanName(displayName), 'role': 'offline_user'},
      );
      _outgoingRequestId = request.id;
      isWaitingForAcceptance = true;
      status = 'Connection request sent to ${peer.label}.';
      notifyListeners();
      await _sendEnvelope(request);
      if (isWaitingForAcceptance) {
        status = 'Connection request sent to ${peer.label}.';
      }
    } finally {
      isConnecting = false;
      notifyListeners();
    }
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
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
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
    _outgoingRequestId = null;
    isDiscovering = false;
    isOffering = false;
    isWaitingForAcceptance = false;
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
    isWaitingForAcceptance = false;
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
    if (current) _connection = null;
    if (incoming) _incomingConnection = null;
    _clearIncomingRequest();
    _outgoingRequestId = null;
    inChat = false;
    isWaitingForAcceptance = false;
    return true;
  }

  void _onEnvelope(RelayConnection connection, Uint8List bytes) {
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
        if (envelope.body['requestId'] != _outgoingRequestId) return;
        isWaitingForAcceptance = false;
        inChat = true;
        status = 'Connection accepted by ${remoteName ?? 'helper'}.';
        notifyListeners();
      case RelayMessageType.connectionReject:
        if (envelope.body['requestId'] != _outgoingRequestId) return;
        isWaitingForAcceptance = false;
        inChat = false;
        status = 'The helper declined the connection request.';
        _connection = null;
        unawaited(connection.close());
        notifyListeners();
      case RelayMessageType.chat:
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

  void _setStatus(String value) {
    status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_incomingSubscription?.cancel());
    unawaited(_availabilitySubscription?.cancel());
    unawaited(_acceptedSubscription?.cancel());
    unawaited(_discoverySubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_transport.dispose());
    super.dispose();
  }
}
