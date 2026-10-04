import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:relay_transport/relay_transport.dart';

import 'transport/helper_availability.dart';
import 'security/relay_secure_session.dart';

enum RelayUserRole { offlineUser, internetHelper }

enum RelayChatEndReason { local, remote, connectionLost, securityFailed }

enum RelayRequestState {
  none,
  pending,
  incoming,
  accepted,
  declined,
  cancelled,
  failed,
}

enum RelaySecurityState { idle, exchangingKeys, ready, failed }

final class RelayLocalReport {
  const RelayLocalReport({
    required this.peerName,
    required this.reason,
    required this.note,
  });

  final String peerName;
  final String reason;
  final String note;
}

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
  RelayDemoController(
    this._transport, {
    this.discoveryDuration = const Duration(seconds: 12),
    this.requestDuration = const Duration(seconds: 60),
    this.securityDuration = const Duration(minutes: 2),
  }) {
    _incomingSubscription = _transport.incomingConnections.listen(
      _onIncomingConnection,
      onError: (Object error) => reportError(error),
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
  final Duration requestDuration;
  final Duration securityDuration;
  final peers = <RelayPeer>[];
  final messages = <RelayConversationMessage>[];
  static const maxHistoryMessages = 300;
  static const maxPendingReceiveMessages = 64;
  int _pendingReceiveMessages = 0;
  int _sessionEpoch = 0;

  void _addMessage(RelayConversationMessage message) {
    messages.add(message);
    if (messages.length > maxHistoryMessages) {
      messages.removeRange(0, messages.length - maxHistoryMessages);
    }
  }

  String displayName = '';
  RelayUserRole role = RelayUserRole.offlineUser;
  String status = 'Choose your name and role to begin.';
  String? remoteName;
  String? remoteRoleLabel;
  String? incomingPeerName;
  String? incomingRequestId;
  bool isDiscovering = false;
  bool isOffering = false;
  bool isConnecting = false;
  bool isWaitingForAcceptance = false;
  bool inChat = false;
  bool isSearchComplete = false;
  String? errorMessage;
  RelayRequestState requestState = RelayRequestState.none;
  RelaySecurityState securityState = RelaySecurityState.idle;
  RelayChatEndReason? chatEndReason;
  bool _localKeyConfirmed = false;
  bool _remoteKeyConfirmed = false;
  Future<void>? _keyExchangeSend;
  RelayLocalReport? submittedReport;

  RelayConnection? _connection;
  RelayConnection? _incomingConnection;
  String? _outgoingRequestId;
  StreamSubscription<RelayConnection>? _incomingSubscription;
  StreamSubscription<HelperAvailabilityState>? _availabilitySubscription;
  StreamSubscription<HelperAcceptedEvent>? _acceptedSubscription;
  StreamSubscription<RelayPeer>? _discoverySubscription;
  StreamSubscription<Uint8List>? _messageSubscription;
  Timer? _discoveryTimer;
  Timer? _requestTimer;
  Timer? _securityTimer;
  bool _disposed = false;
  bool _responding = false;
  Future<void> _sendQueue = Future<void>.value();
  Future<void> _secureSendQueue = Future<void>.value();
  RelaySecureSession? _secureSession;
  bool _isSessionInitiator = false;
  bool _localEndRequested = false;
  bool _localReportSubmitted = false;
  Future<void> _receiveQueue = Future<void>.value();

  bool get hasIncomingRequest =>
      _incomingConnection != null && incomingRequestId != null;

  bool get noPeopleFound =>
      isSearchComplete && peers.isEmpty && errorMessage == null;
  bool get isChatTerminal => chatEndReason != null;
  bool get hasSubmittedReport => _localReportSubmitted;
  bool get isResponding => _responding;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _closeConnection(RelayConnection connection) async {
    try {
      await connection.close();
    } catch (error) {
      if (!_disposed) reportError(error);
    }
  }

  void _startRequestDeadline(RelayConnection connection) {
    _requestTimer?.cancel();
    _requestTimer = Timer(requestDuration, () {
      _onConnectionEnded(
        connection,
        'The connection request timed out. Try again.',
      );
      unawaited(_closeConnection(connection));
    });
  }

  RelayProfile get localProfile => RelayProfile(
    id: 'local-${DateTime.now().microsecondsSinceEpoch}',
    label: _cleanName(displayName),
    metadata: {'role': _roleWireName(role)},
  );

  void updateProfile({required String name, required RelayUserRole role}) {
    displayName = name;
    this.role = role;
    notifyListeners();
  }

  Future<void> findNearbyHelpers() async {
    if (_disposed ||
        isConnecting ||
        isWaitingForAcceptance ||
        _incomingConnection != null ||
        inChat) {
      return;
    }
    _requireName();
    if (role != RelayUserRole.offlineUser) {
      throw StateError('Choose Offline User to find helpers.');
    }
    await _discoverySubscription?.cancel();
    _discoveryTimer?.cancel();
    peers.clear();
    isOffering = false;
    isDiscovering = true;
    isSearchComplete = false;
    errorMessage = null;
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
        unawaited(_discoverySubscription?.cancel());
        _discoverySubscription = null;
        _setStatus('Discovery stopped: $error');
      },
    );
    _discoveryTimer = Timer(discoveryDuration, () {
      if (!isDiscovering) return;
      isDiscovering = false;
      isSearchComplete = true;
      status = peers.isEmpty
          ? 'No one found nearby.'
          : '${peers.length} nearby helper${peers.length == 1 ? '' : 's'} found.';
      unawaited(_discoverySubscription?.cancel());
      _discoverySubscription = null;
      notifyListeners();
    });
  }

  Future<void> offerHelp() async {
    if (_disposed ||
        isConnecting ||
        isWaitingForAcceptance ||
        _incomingConnection != null ||
        inChat) {
      return;
    }
    _requireName();
    if (role != RelayUserRole.internetHelper) {
      throw StateError('Choose Internet Helper to offer help.');
    }
    await _discoverySubscription?.cancel();
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
    errorMessage = null;
    status = 'Help Others is off.';
    notifyListeners();
  }

  Future<void> connectTo(RelayPeer peer) async {
    if (_disposed ||
        isConnecting ||
        isWaitingForAcceptance ||
        _connection != null ||
        _incomingConnection != null ||
        inChat) {
      return;
    }
    _requireName();
    // Validate metadata before opening GATT so a long UTF-8 name cannot strand a link.
    final request = RelayEnvelope.create(
      type: RelayMessageType.connectionRequest,
      body: {'name': _cleanName(displayName), 'role': 'offline_user'},
    );
    request.encode();
    final epoch = ++_sessionEpoch;
    messages.clear();
    isConnecting = true;
    remoteName = peer.label;
    errorMessage = null;
    requestState = RelayRequestState.none;
    _discoveryTimer?.cancel();
    status = 'Connecting to ${peer.label}…';
    notifyListeners();
    try {
      final connection = await _transport.connect(peer);
      if (_disposed ||
          epoch != _sessionEpoch ||
          requestState == RelayRequestState.cancelled) {
        await _closeConnection(connection);
        return;
      }
      _connection = connection;
      remoteName = peer.label;
      remoteRoleLabel = 'Internet Helper';
      _isSessionInitiator = true;
      requestState = RelayRequestState.pending;
      _listenForMessages(connection);
      await _discoverySubscription?.cancel();
      _discoverySubscription = null;
      isDiscovering = false;
      _outgoingRequestId = request.id;
      isWaitingForAcceptance = true;
      _startRequestDeadline(connection);
      status = 'Connection request sent to ${peer.label}.';
      notifyListeners();
      await _sendEnvelope(request);
      if (isWaitingForAcceptance) {
        status = 'Connection request sent to ${peer.label}.';
      }
    } catch (error) {
      if (_disposed ||
          epoch != _sessionEpoch ||
          requestState == RelayRequestState.cancelled) {
        return;
      }
      _requestTimer?.cancel();
      final failedConnection = _connection;
      _connection = null;
      isWaitingForAcceptance = false;
      if (failedConnection != null) await _closeConnection(failedConnection);
      isDiscovering = false;
      isSearchComplete = true;
      _discoveryTimer?.cancel();
      await _discoverySubscription?.cancel();
      _discoverySubscription = null;
      errorMessage = _friendlyError(error);
      requestState = RelayRequestState.failed;
      status = 'Couldn’t connect to ${peer.label}.';
      rethrow;
    } finally {
      if (epoch == _sessionEpoch) {
        isConnecting = false;
        notifyListeners();
      }
    }
  }

  Future<void> acceptIncomingRequest() async {
    if (_responding || _disposed) return;
    final connection = _incomingConnection;
    final requestId = incomingRequestId;
    if (connection == null || requestId == null) {
      throw StateError('There is no connection request to accept.');
    }
    _responding = true;
    final epoch = _sessionEpoch;
    notifyListeners();
    _requestTimer?.cancel();
    try {
      _connection = connection;
      remoteName = incomingPeerName ?? connection.peer.label;
      remoteRoleLabel = 'Offline User';
      _isSessionInitiator = false;
      incomingPeerName = null;
      incomingRequestId = null;
      _incomingConnection = null;
      await _transport.stopAdvertising();
      if (_disposed ||
          epoch != _sessionEpoch ||
          !identical(connection, _connection)) {
        return;
      }
      isOffering = false;
      inChat = true;
      requestState = RelayRequestState.accepted;
      _resetSecureState();
      await _createSecureSession(isInitiator: false, sendKey: false);
      notifyListeners();
      await _sendEnvelope(
        RelayEnvelope.create(
          type: RelayMessageType.connectionAccept,
          body: {'requestId': requestId},
        ),
      );
      await _sendKeyExchange();
      status = 'Connected with $remoteName.';
      notifyListeners();
    } catch (error) {
      _finishChat(RelayChatEndReason.connectionLost, connection);
      if (epoch == _sessionEpoch) rethrow;
    } finally {
      _responding = false;
      notifyListeners();
    }
  }

  Future<void> rejectIncomingRequest() async {
    if (_responding || _disposed) return;
    final connection = _incomingConnection;
    final requestId = incomingRequestId;
    if (connection == null || requestId == null) return;
    _responding = true;
    notifyListeners();
    _requestTimer?.cancel();
    try {
      await connection.send(
        RelayEnvelope.create(
          type: RelayMessageType.connectionReject,
          body: {'requestId': requestId},
        ).encode(),
      );
    } finally {
      _incomingConnection = null;
      _clearIncomingRequest();
      await _closeConnection(connection);
      _responding = false;
      notifyListeners();
    }
    requestState = RelayRequestState.declined;
    isOffering = role == RelayUserRole.internetHelper;
    status = isOffering
        ? 'Connection declined. You are still offering help.'
        : 'Connection declined.';
    notifyListeners();
  }

  Future<void> sendChat(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    if (securityState != RelaySecurityState.ready) {
      throw StateError('Encrypted chat is still connecting. Please wait.');
    }
    final connection = _connection;
    final envelope = await _sendSecurePayload(RelayMessageType.chat, {
      'text': value,
    });
    if (_disposed || !identical(connection, _connection) || !inChat) return;
    _addMessage(
      RelayConversationMessage(
        id: envelope.id,
        text: value,
        fromLocalUser: true,
      ),
    );
    notifyListeners();
  }

  void reportError(Object error) {
    errorMessage = _friendlyError(error);
    status = errorMessage!;
    notifyListeners();
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> endChat() async {
    final connection = _connection;
    if (!inChat || connection == null || chatEndReason != null) return;
    _localEndRequested = true;
    errorMessage = null;
    try {
      if (securityState == RelaySecurityState.ready) {
        await _sendSecurePayload(RelayMessageType.endChat, const {});
      } else {
        await _sendEnvelope(
          RelayEnvelope.create(type: RelayMessageType.endChat, body: const {}),
        );
      }
    } catch (_) {
      errorMessage = 'Chat ended on this phone. The other phone may not have received the end notice.';
    } finally {
      _finishChat(RelayChatEndReason.local, connection);
    }
  }

  void submitLocalReport({required String reason, String note = ''}) {
    if (!inChat || securityState != RelaySecurityState.ready) {
      throw StateError('A report can only be recorded during an active chat.');
    }
    submittedReport = RelayLocalReport(
      peerName: remoteName ?? 'Nearby user',
      reason: reason,
      note: note.trim(),
    );
    _localReportSubmitted = true;
    notifyListeners();
  }

  Future<void> cancelPendingRequest() async {
    if (!isWaitingForAcceptance && !isConnecting) return;
    _requestTimer?.cancel();
    requestState = RelayRequestState.cancelled;
    final connection = _connection;
    _connection = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    if (connection != null) {
      try {
        await connection.send(
          RelayEnvelope.create(
            type: RelayMessageType.connectionCancel,
            body: {'requestId': _outgoingRequestId},
          ).encode(),
        );
      } catch (_) {
        // Closing the GATT connection still cancels the local pending request.
      }
    }
    if (connection != null) await _closeConnection(connection);
    isWaitingForAcceptance = false;
    requestState = RelayRequestState.cancelled;
    status = 'Connection request cancelled.';
    notifyListeners();
  }

  Future<void> returnToNearby() async {
    ++_sessionEpoch;
    _pendingReceiveMessages = 0;
    _receiveQueue = Future<void>.value();
    isConnecting = false;
    _requestTimer?.cancel();
    _securityTimer?.cancel();
    _discoveryTimer?.cancel();
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    final connection = _connection ?? _incomingConnection;
    _connection = null;
    _incomingConnection = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    _secureSession?.close();
    _secureSession = null;
    if (connection != null) await _closeConnection(connection);
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
    remoteRoleLabel = null;
    _outgoingRequestId = null;
    isDiscovering = false;
    isSearchComplete = false;
    isOffering = false;
    isWaitingForAcceptance = false;
    inChat = false;
    requestState = RelayRequestState.none;
    chatEndReason = null;
    submittedReport = null;
    _localReportSubmitted = false;
    _resetSecureState();
    status = 'Choose Find Nearby Helpers or Offer Help.';
    errorMessage = null;
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
    chatEndReason = null;
    _startRequestDeadline(connection);
    incomingPeerName = connection.peer.label;
    requestState = RelayRequestState.incoming;
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
    if (inChat || isChatTerminal || _disposed) return;
    if (role != RelayUserRole.internetHelper ||
        _incomingConnection == null ||
        !identical(event.connection, _incomingConnection) ||
        event.requestId == null ||
        (incomingRequestId != null && event.requestId != incomingRequestId)) {
      return;
    }
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
    // Restored native acceptance has no matching in-memory keys after engine loss.
    if (_connection case final connection?) {
      _finishChat(RelayChatEndReason.connectionLost, connection);
    }
  }

  void _listenForMessages(RelayConnection connection) {
    final epoch = _sessionEpoch;
    _sendQueue = Future<void>.value();
    _secureSendQueue = Future<void>.value();
    _pendingReceiveMessages = 0;
    _receiveQueue = Future<void>.value();
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = connection.messages.listen(
      (bytes) {
        if (_disposed ||
            epoch != _sessionEpoch ||
            (!identical(_connection, connection) &&
                !identical(_incomingConnection, connection))) {
          return;
        }
        if (bytes.isEmpty || bytes.length > relayMaxMessageBytes) return;
        if (_pendingReceiveMessages >= maxPendingReceiveMessages) {
          _onConnectionEnded(
            connection,
            'Too many pending messages. Reconnect to continue.',
          );
          unawaited(_closeConnection(connection));
          return;
        }
        ++_pendingReceiveMessages;
        _receiveQueue = _receiveQueue.then((_) async {
          try {
            if (_disposed ||
                epoch != _sessionEpoch ||
                chatEndReason != null ||
                (!identical(_connection, connection) &&
                    !identical(_incomingConnection, connection))) {
              return;
            }
            try {
              await _onEnvelope(connection, bytes);
            } catch (error) {
              if (epoch == _sessionEpoch) reportError(error);
            }
          } finally {
            if (epoch == _sessionEpoch) --_pendingReceiveMessages;
          }
        });
      },
      onError: (Object error) {
        _onConnectionEnded(connection, error.toString());
      },
      onDone: () {
        _onConnectionEnded(connection, 'Connection closed.');
      },
    );
  }

  Future<void> _onEnvelope(RelayConnection connection, Uint8List bytes) async {
    late final RelayEnvelope envelope;
    try {
      envelope = RelayEnvelope.decode(bytes);
    } catch (error) {
      reportError(error);
      return;
    }
    switch (envelope.type) {
      case RelayMessageType.connectionRequest:
        if (role != RelayUserRole.internetHelper ||
            !identical(_incomingConnection, connection)) {
          return;
        }
        if (incomingRequestId != null) return;
        final name = _bodyString(envelope, 'name');
        if (name == null ||
            name.trim().isEmpty ||
            envelope.body['role'] != 'offline_user') {
          return;
        }
        incomingRequestId = envelope.id;
        incomingPeerName = name;
        remoteRoleLabel = _roleLabel(_bodyString(envelope, 'role'));
        requestState = RelayRequestState.incoming;
        status = 'Connection request from $incomingPeerName.';
        notifyListeners();
      case RelayMessageType.connectionAccept:
        if (!identical(connection, _connection) ||
            _outgoingRequestId == null ||
            !isWaitingForAcceptance ||
            envelope.body['requestId'] != _outgoingRequestId) {
          return;
        }
        _requestTimer?.cancel();
        isWaitingForAcceptance = false;
        inChat = true;
        requestState = RelayRequestState.accepted;
        _resetSecureState();
        status = 'Connection accepted by ${remoteName ?? 'helper'}.';
        notifyListeners();
        await _createSecureSession(isInitiator: true);
      case RelayMessageType.connectionReject:
        if (!identical(connection, _connection) ||
            _outgoingRequestId == null ||
            !isWaitingForAcceptance ||
            envelope.body['requestId'] != _outgoingRequestId) {
          return;
        }
        _requestTimer?.cancel();
        isWaitingForAcceptance = false;
        inChat = false;
        requestState = RelayRequestState.declined;
        status = 'The helper declined the connection request.';
        _connection = null;
        await connection.close();
        notifyListeners();
      case RelayMessageType.connectionCancel:
        if (!identical(_incomingConnection, connection) ||
            envelope.body['requestId'] != incomingRequestId) {
          return;
        }
        _requestTimer?.cancel();
        _incomingConnection = null;
        _clearIncomingRequest();
        requestState = RelayRequestState.cancelled;
        status = 'The connection request was cancelled.';
        await connection.close();
        notifyListeners();
      case RelayMessageType.chat:
      // Chat envelopes are accepted only inside authenticated encrypted packets.
      case RelayMessageType.keyExchange:
        if (envelope.type == RelayMessageType.keyExchange) {
          await _handleKeyExchange(connection, envelope);
        }
      case RelayMessageType.keyConfirmation:
        // Key confirmation is carried only inside an authenticated encrypted packet.
        return;
      case RelayMessageType.secureMessage:
        await _handleSecureMessage(connection, envelope);
      case RelayMessageType.endChat:
        if (inChat && securityState != RelaySecurityState.ready) {
          _finishChat(RelayChatEndReason.remote, connection);
        }
      case RelayMessageType.serviceRequest:
      case RelayMessageType.serviceResponse:
      // Reserved by the shared transport contract; this MVP treats them as
      // unsupported messages and keeps the chat flow text-only.
    }
  }

  Future<void> _sendEnvelope(RelayEnvelope envelope) async {
    final connection = _connection;
    if (connection == null) throw StateError('Connect first.');
    final bytes = envelope.encode();
    final send = _sendQueue.then((_) async {
      if (_disposed || !identical(connection, _connection)) {
        throw StateError('Connection is closed.');
      }
      await connection.send(bytes);
    });
    _sendQueue = send.catchError((Object _) {});
    await send;
  }

  Future<void> _createSecureSession({
    required bool isInitiator,
    bool sendKey = true,
  }) async {
    if (_secureSession != null) return;
    final connection = _connection;
    final session = await RelaySecureSession.create(isInitiator: isInitiator);
    if (_disposed || !inChat || !identical(connection, _connection)) {
      session.close();
      return;
    }
    _secureSession = session;
    securityState = RelaySecurityState.exchangingKeys;
    _securityTimer?.cancel();
    _securityTimer = Timer(securityDuration, () {
      if (securityState != RelaySecurityState.ready) {
        unawaited(_endForSecurityFailure(connection!));
      }
    });
    if (sendKey) await _sendKeyExchange();
  }

  Future<void> _sendKeyExchange() => _keyExchangeSend ??= _sendOwnPublicKey();

  Future<void> _sendOwnPublicKey() async {
    final secureSession = _secureSession;
    if (secureSession == null) {
      throw StateError('Secure session is unavailable.');
    }
    await _sendEnvelope(
      RelayEnvelope.create(
        type: RelayMessageType.keyExchange,
        body: {'publicKey': await secureSession.publicKeyBase64},
      ),
    );
  }

  Future<void> _handleKeyExchange(
    RelayConnection connection,
    RelayEnvelope envelope,
  ) async {
    if (!inChat) return;
    if (_secureSession == null) {
      await _createSecureSession(isInitiator: _isSessionInitiator);
    }
    if (securityState != RelaySecurityState.exchangingKeys ||
        _localKeyConfirmed) {
      return;
    }
    final publicKey = _bodyString(envelope, 'publicKey');
    if (publicKey == null) {
      await _endForSecurityFailure(connection);
      return;
    }
    try {
      final session = _secureSession!;
      await session.establish(publicKey);
      if (_disposed || !inChat || !identical(session, _secureSession)) return;
      // Send our public key before confirmation, including when the peer key
      // arrives while the helper's acceptance is still waiting for its ACK.
      await _sendKeyExchange();
      await _sendSecurePayload(RelayMessageType.keyConfirmation, {
        'confirm': true,
      });
      if (_disposed || !inChat || !identical(session, _secureSession)) return;
      _localKeyConfirmed = true;
      _updateSecurityReady();
      notifyListeners();
    } catch (_) {
      await _endForSecurityFailure(connection);
    }
  }

  Future<void> _handleSecureMessage(
    RelayConnection connection,
    RelayEnvelope envelope,
  ) async {
    final secureSession = _secureSession;
    final counter = envelope.body['n'];
    final ciphertext = envelope.body['c'];
    if (secureSession == null || counter is! int || ciphertext is! String) {
      await _endForSecurityFailure(connection);
      return;
    }
    try {
      final cleartext = await secureSession.decrypt(
        counter: counter,
        ciphertext: ciphertext,
      );
      if (_disposed ||
          !inChat ||
          !identical(secureSession, _secureSession) ||
          !identical(connection, _connection)) {
        return;
      }
      final decoded = jsonDecode(utf8.decode(cleartext));
      if (decoded is! Map<String, dynamic> ||
          decoded['t'] is! String ||
          decoded['b'] is! Map<String, dynamic>) {
        throw const FormatException('Malformed encrypted application message.');
      }
      final type = RelayMessageType.parse(decoded['t'] as String);
      final body = Map<String, Object?>.from(
        decoded['b'] as Map<String, dynamic>,
      );
      switch (type) {
        case RelayMessageType.keyConfirmation:
          if (securityState != RelaySecurityState.exchangingKeys ||
              body['confirm'] != true) {
            await _endForSecurityFailure(connection);
            return;
          }
          _remoteKeyConfirmed = true;
          _updateSecurityReady();
          notifyListeners();
        case RelayMessageType.chat:
          if (securityState != RelaySecurityState.ready) {
            await _endForSecurityFailure(connection);
            return;
          }
          final text = body['text'];
          if (text is! String || text.trim().isEmpty) return;
          _addMessage(
            RelayConversationMessage(
              id: envelope.id,
              text: text,
              fromLocalUser: false,
            ),
          );
          notifyListeners();
        case RelayMessageType.endChat:
          if (securityState != RelaySecurityState.ready) {
            await _endForSecurityFailure(connection);
            return;
          }
          _finishChat(RelayChatEndReason.remote, connection);
        default:
          await _endForSecurityFailure(connection);
      }
    } catch (_) {
      await _endForSecurityFailure(connection);
    }
  }

  Future<RelayEnvelope> _sendSecurePayload(
    RelayMessageType type,
    Map<String, Object?> body,
  ) {
    final session = _secureSession;
    final send = _secureSendQueue.then((_) {
      if (!identical(session, _secureSession)) {
        throw StateError('Connection is closed.');
      }
      return _encryptAndSend(type, body);
    });
    _secureSendQueue = send.then<void>((_) {}, onError: (Object _) {});
    return send;
  }

  Future<RelayEnvelope> _encryptAndSend(
    RelayMessageType type,
    Map<String, Object?> body,
  ) async {
    final secureSession = _secureSession;
    if (secureSession == null ||
        (securityState != RelaySecurityState.ready &&
            type != RelayMessageType.keyConfirmation)) {
      throw StateError('Secure session is not ready.');
    }
    final cleartext = utf8.encode(jsonEncode({'t': type.wireName, 'b': body}));
    final frame = await secureSession.encrypt(cleartext);
    if (_disposed || !inChat || !identical(secureSession, _secureSession)) {
      throw StateError('Connection is closed.');
    }
    final envelope = RelayEnvelope(
      id: 's${frame.counter.toRadixString(36)}',
      type: RelayMessageType.secureMessage,
      body: {'n': frame.counter, 'c': frame.ciphertext},
    );
    try {
      envelope.encode();
    } on FormatException {
      throw StateError(
        'This message is too long for nearby chat. Shorten it and try again.',
      );
    }
    await _sendEnvelope(envelope);
    return envelope;
  }

  void _updateSecurityReady() {
    if (_localKeyConfirmed && _remoteKeyConfirmed) {
      _securityTimer?.cancel();
      securityState = RelaySecurityState.ready;
      status = 'Secure chat with $remoteName is ready.';
    }
  }

  Future<void> _endForSecurityFailure(RelayConnection connection) async {
    if (identical(connection, _connection)) {
      _finishChat(RelayChatEndReason.securityFailed, connection);
    }
  }

  void _finishChat(RelayChatEndReason reason, RelayConnection connection) {
    if (chatEndReason != null ||
        (!identical(connection, _connection) &&
            !identical(connection, _incomingConnection))) {
      return;
    }
    ++_sessionEpoch;
    _pendingReceiveMessages = 0;
    chatEndReason = reason;
    _requestTimer?.cancel();
    _securityTimer?.cancel();
    _localEndRequested = false;
    inChat = false;
    isWaitingForAcceptance = false;
    if (identical(_connection, connection)) _connection = null;
    if (identical(_incomingConnection, connection)) _incomingConnection = null;
    _secureSession?.close();
    _secureSession = null;
    securityState = reason == RelayChatEndReason.securityFailed
        ? RelaySecurityState.failed
        : RelaySecurityState.idle;
    status = switch (reason) {
      RelayChatEndReason.local => 'You ended this chat.',
      RelayChatEndReason.remote => '$remoteName ended this chat.',
      RelayChatEndReason.connectionLost => 'The connection was lost.',
      RelayChatEndReason.securityFailed =>
        'Encrypted session setup failed. The chat was closed.',
    };
    unawaited(_closeConnection(connection));
    notifyListeners();
  }

  void _onConnectionEnded(RelayConnection connection, String message) {
    if (_disposed || chatEndReason != null) return;
    if (identical(_connection, connection) ||
        identical(_incomingConnection, connection)) {
      if (inChat) {
        _finishChat(
          _localEndRequested
              ? RelayChatEndReason.local
              : RelayChatEndReason.connectionLost,
          connection,
        );
      } else {
        _requestTimer?.cancel();
        _connection = null;
        _incomingConnection = null;
        isWaitingForAcceptance = false;
        _clearIncomingRequest();
        requestState = RelayRequestState.failed;
        errorMessage = message.contains('timed out')
            ? message
            : 'The nearby connection ended before chat started. Try again.';
        status = errorMessage!;
        notifyListeners();
      }
    }
  }

  String _roleLabel(String? role) => role == 'internet_helper'
      ? 'Internet Helper'
      : role == 'offline_user'
      ? 'Offline User'
      : 'Nearby person';

  void _resetSecureState() {
    _secureSession?.close();
    _secureSession = null;
    securityState = RelaySecurityState.idle;
    _localKeyConfirmed = false;
    _remoteKeyConfirmed = false;
    _keyExchangeSend = null;
    chatEndReason = null;
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

  String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Bad state: ', '');
    if (value.toLowerCase().contains('permission')) {
      return value.toLowerCase().contains('notification')
          ? 'Allow notifications in Android Settings > Apps > OfflineRelay > Notifications, then enable Help Others again.'
          : 'Nearby permissions are needed. Allow Nearby devices in Android Settings > Apps > OfflineRelay > Permissions, then try again.';
    }
    if (value.toLowerCase().contains('bluetooth')) {
      return 'Turn on Bluetooth to find and connect with nearby helpers.';
    }
    if (value.contains('Encoded envelope')) {
      return 'Your name is too long for nearby connection setup. Use a shorter name and try again.';
    }
    if (value.contains('PlatformException')) {
      if (value.toLowerCase().contains('timeout')) {
        return 'The nearby connection timed out. Keep both phones close and try again.';
      }
      return 'The nearby connection could not complete. Check Bluetooth and try again.';
    }
    return value;
  }

  @override
  void dispose() {
    _disposed = true;
    _requestTimer?.cancel();
    _securityTimer?.cancel();
    _secureSession?.close();
    _discoveryTimer?.cancel();
    unawaited(_incomingSubscription?.cancel());
    unawaited(_availabilitySubscription?.cancel());
    unawaited(_acceptedSubscription?.cancel());
    unawaited(_discoverySubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_transport.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
