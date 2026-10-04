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
  static const maxHistoryMessages = 300;
  static const _maxRecentIncomingIds = 1024;

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
  final _recentIncomingIds = <String>{};

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
  String? _acceptingRequestId;
  int _sessionEpoch = 0;
  bool _disposed = false;
  Timer? _incomingSetupTimer;
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
    if (isConnecting || _connection != null || _incomingConnection != null) {
      throw StateError('Finish the current connection first.');
    }
    final epoch = ++_sessionEpoch;
    messages.clear();
    isConnecting = true;
    status = 'Connecting to ${peer.label}…';
    notifyListeners();
    try {
      final connection = await _transport.connect(peer);
      if (_disposed || epoch != _sessionEpoch) {
        await connection.close();
        return;
      }
      _connection = connection;
      remoteName = peer.label;
      _listenForMessages(connection);
      await _discoverySubscription?.cancel();
      if (!_isCurrent(connection) || epoch != _sessionEpoch) return;
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
      if (_isCurrent(connection) && isWaitingForAcceptance) {
        status = 'Connection request sent to ${peer.label}.';
      }
    } catch (error) {
      if (!_disposed && epoch == _sessionEpoch) {
        final connection = _connection;
        _clearSession();
        if (connection != null) unawaited(connection.close());
        _setStatus('Connection failed: $error');
      }
      rethrow;
    } finally {
      if (!_disposed && epoch == _sessionEpoch) {
        isConnecting = false;
        notifyListeners();
      }
    }
  }

  Future<void> acceptIncomingRequest() async {
    final connection = _incomingConnection;
    final requestId = incomingRequestId;
    if (connection == null || requestId == null) {
      throw StateError('There is no connection request to accept.');
    }
    _connection = connection;
    _acceptingRequestId = requestId;
    remoteName = incomingPeerName ?? connection.peer.label;
    incomingPeerName = null;
    incomingRequestId = null;
    _incomingConnection = null;
    try {
      await _transport.stopAdvertising();
      if (!_isCurrent(connection)) return;
      isOffering = false;
      await _sendEnvelope(
        RelayEnvelope.create(
          type: RelayMessageType.connectionAccept,
          body: {'requestId': requestId},
        ),
      );
      if (!_isCurrent(connection)) return;
      inChat = true;
      _acceptingRequestId = null;
      status = 'Connected with $remoteName.';
      notifyListeners();
    } catch (error) {
      _endConnection(connection, 'Acceptance failed: $error');
      await connection.close();
      rethrow;
    }
  }

  Future<void> rejectIncomingRequest() async {
    final connection = _incomingConnection;
    final requestId = incomingRequestId;
    if (connection == null || requestId == null) return;
    try {
      await connection.send(
        RelayEnvelope.create(
          type: RelayMessageType.connectionReject,
          body: {'requestId': requestId},
        ).encode(),
      );
    } finally {
      _endConnection(connection, 'Connection request declined.');
      await connection.close();
      if (!_disposed && role == RelayUserRole.internetHelper) {
        isOffering = true;
        _setStatus('Connection declined. You are still offering help.');
      }
    }
  }

  Future<void> sendChat(String text) async {
    final connection = _connection;
    if (_disposed || !inChat || connection == null) {
      throw StateError('Wait for connection approval before sending chat.');
    }
    final epoch = _sessionEpoch;
    final value = text.trim();
    if (value.isEmpty) return;
    final envelope = RelayEnvelope.create(
      type: RelayMessageType.chat,
      body: {'text': value},
    );
    await _sendEnvelope(envelope);
    if (!_isCurrent(connection) || epoch != _sessionEpoch || !inChat) return;
    _appendMessage(
      RelayConversationMessage(
        id: envelope.id,
        text: value,
        fromLocalUser: true,
      ),
    );
    notifyListeners();
  }

  Future<void> returnToNearby() async {
    final connection = _connection ?? _incomingConnection;
    // Invalidate pending asynchronous work before any awaited cleanup.
    _clearSession();
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
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
    isDiscovering = false;
    isOffering = false;
    if (_disposed) return;
    status = 'Choose Find Nearby Helpers or Offer Help.';
    notifyListeners();
  }

  void _onIncomingConnection(RelayConnection connection) {
    if (_disposed ||
        role != RelayUserRole.internetHelper ||
        _incomingConnection != null ||
        _connection != null) {
      unawaited(connection.close());
      return;
    }
    _incomingConnection = connection;
    ++_sessionEpoch;
    messages.clear();
    incomingPeerName = connection.peer.label;
    _listenForMessages(connection);
    _incomingSetupTimer = Timer(const Duration(seconds: 15), () {
      if (!_isCurrent(connection) || incomingRequestId != null) return;
      _endConnection(connection, 'Connection request timed out.');
      unawaited(connection.close());
    });
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
    final current = _incomingConnection ?? _connection;
    final expectedRequest = incomingRequestId ?? _acceptingRequestId;
    if (_disposed ||
        role != RelayUserRole.internetHelper ||
        inChat ||
        current == null ||
        !identical(event.connection, current) ||
        expectedRequest == null ||
        event.requestId != expectedRequest) {
      return;
    }
    _incomingSetupTimer?.cancel();
    _incomingSetupTimer = null;
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
        _endConnection(connection, 'Connection ended: $error');
      },
      onDone: () {
        _endConnection(connection, 'Connection closed.');
      },
    );
  }

  void _onEnvelope(RelayConnection connection, Uint8List bytes) {
    if (!_isCurrent(connection)) return;
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
            !identical(_incomingConnection, connection) ||
            incomingRequestId != null) {
          return;
        }
        final name = _bodyString(envelope, 'name');
        if (name == null ||
            name.trim().isEmpty ||
            envelope.body['role'] != 'offline_user') {
          return;
        }
        incomingRequestId = envelope.id;
        _incomingSetupTimer?.cancel();
        _incomingSetupTimer = null;
        incomingPeerName =
            _bodyString(envelope, 'name') ?? connection.peer.label;
        status = 'Connection request from $incomingPeerName.';
        notifyListeners();
      case RelayMessageType.connectionAccept:
        if (!_matchesOutgoingRequest(connection, envelope)) return;
        _outgoingRequestId = null;
        isWaitingForAcceptance = false;
        inChat = true;
        status = 'Connection accepted by ${remoteName ?? 'helper'}.';
        notifyListeners();
      case RelayMessageType.connectionReject:
        if (!_matchesOutgoingRequest(connection, envelope)) return;
        _endConnection(
          connection,
          'The helper declined the connection request.',
        );
        unawaited(connection.close());
      case RelayMessageType.chat:
        if (!inChat || !identical(_connection, connection)) return;
        final text = _bodyString(envelope, 'text');
        if (text == null) return;
        if (!_recentIncomingIds.add(envelope.id)) return;
        if (_recentIncomingIds.length > _maxRecentIncomingIds) {
          _recentIncomingIds.remove(_recentIncomingIds.first);
        }
        _appendMessage(
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

  void _appendMessage(RelayConversationMessage message) {
    messages.add(message);
    if (messages.length > maxHistoryMessages) {
      messages.removeRange(0, messages.length - maxHistoryMessages);
    }
  }

  bool _isCurrent(RelayConnection connection) =>
      !_disposed &&
      (identical(_connection, connection) ||
          identical(_incomingConnection, connection));

  bool _matchesOutgoingRequest(
    RelayConnection connection,
    RelayEnvelope envelope,
  ) =>
      role == RelayUserRole.offlineUser &&
      identical(_connection, connection) &&
      isWaitingForAcceptance &&
      !inChat &&
      _outgoingRequestId != null &&
      envelope.body['requestId'] == _outgoingRequestId;

  void _clearSession() {
    _incomingSetupTimer?.cancel();
    _incomingSetupTimer = null;
    ++_sessionEpoch;
    _connection = null;
    _incomingConnection = null;
    _outgoingRequestId = null;
    _acceptingRequestId = null;
    _clearIncomingRequest();
    remoteName = null;
    messages.clear();
    _recentIncomingIds.clear();
    inChat = false;
    isConnecting = false;
    isWaitingForAcceptance = false;
    isOffering = false;
  }

  void _endConnection(RelayConnection connection, String reason) {
    if (!_isCurrent(connection)) return;
    _clearSession();
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    _setStatus(reason);
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
    if (_disposed) throw StateError('Controller has been disposed.');
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
    _disposed = true;
    _clearSession();
    unawaited(_incomingSubscription?.cancel());
    unawaited(_availabilitySubscription?.cancel());
    unawaited(_acceptedSubscription?.cancel());
    unawaited(_discoverySubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_transport.dispose());
    super.dispose();
  }
}
