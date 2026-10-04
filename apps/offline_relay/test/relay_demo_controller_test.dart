import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:relay_transport/relay_transport.dart';
import 'package:offline_relay/security/relay_secure_session.dart';

import 'package:offline_relay/transport/helper_availability.dart';

void main() {
  test(
    'two controllers complete overlapping key exchange and bidirectional chat',
    () async {
      final requesterTransport = _FakeTransport();
      final helperTransport = _FakeTransport();
      requesterTransport.connection.deliverTo = helperTransport.connection;
      helperTransport.connection.deliverTo = requesterTransport.connection;
      requesterTransport.connection.sendDelay = const Duration(
        milliseconds: 15,
      );
      helperTransport.connection.sendDelay = const Duration(milliseconds: 15);
      final requester = RelayDemoController(requesterTransport);
      final helper = RelayDemoController(helperTransport);
      requester.updateProfile(
        name: 'Requester',
        role: RelayUserRole.offlineUser,
      );
      helper.updateProfile(name: 'Helper', role: RelayUserRole.internetHelper);
      await helper.offerHelp();
      helperTransport.incoming.add(helperTransport.connection);
      await _flushEvents();
      await requester.connectTo(_helperPeer);
      await _waitFor(() => helper.hasIncomingRequest);
      await helper.acceptIncomingRequest();
      await _waitFor(
        () =>
            requester.securityState == RelaySecurityState.ready &&
            helper.securityState == RelaySecurityState.ready,
      );
      await Future.wait([
        requester.sendChat('from requester'),
        helper.sendChat('from helper'),
      ]);
      await _waitFor(
        () => requester.messages.length == 2 && helper.messages.length == 2,
      );
      expect(requester.messages.map((message) => message.text).toSet(), {
        'from requester',
        'from helper',
      });
      await requester.endChat();
      await _waitFor(() => helper.isChatTerminal);
      expect(helper.chatEndReason, RelayChatEndReason.remote);
      await _dispose(requester);
      await _dispose(helper);
    },
  );
  test(
    'encryption is established without user confirmation',
    () async {
      final session = await _offlineConnected();
      expect(session.controller.securityState, RelaySecurityState.ready);
      await _dispose(session.controller);
    },
  );

  test(
    'concurrent chat sends are serialized and preserve counter order',
    () async {
      final session = await _offlineConnected();
      session.transport.connection.sendDelay = const Duration(milliseconds: 10);
      await Future.wait([
        session.controller.sendChat('first'),
        session.controller.sendChat('second'),
      ]);
      expect(session.controller.messages.map((message) => message.text), [
        'first',
        'second',
      ]);
      final frames = session.transport.connection.sent
          .map(RelayEnvelope.decode)
          .where((envelope) => envelope.type == RelayMessageType.secureMessage)
          .toList();
      expect(frames.map((frame) => frame.body['n']), [0, 1, 2]);
      await _dispose(session.controller);
    },
  );

  test('oversized UTF-8 chat fails without losing the session', () async {
    final session = await _offlineConnected();
    await expectLater(
      session.controller.sendChat(List.filled(80, '🌍').join()),
      throwsStateError,
    );
    expect(session.controller.messages, isEmpty);
    expect(session.controller.inChat, isTrue);
    await session.controller.sendChat('short retry');
    expect(session.controller.messages.single.text, 'short retry');
    expect(
      session.transport.connection.sent.every((bytes) => bytes.length <= 256),
      isTrue,
    );
    await _dispose(session.controller);
  });

  test('failed request send releases the link and waiting state', () async {
    final transport = _FakeTransport();
    transport.connection.failNextSend = true;
    final controller = RelayDemoController(transport);
    controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);
    await expectLater(controller.connectTo(_helperPeer), throwsStateError);
    expect(controller.isWaitingForAcceptance, isFalse);
    expect(controller.isConnecting, isFalse);
    expect(transport.connection.isClosed, isTrue);
    expect(controller.requestState, RelayRequestState.failed);
    await _dispose(controller);
  });

  test('unanswered request times out and closes its connection', () async {
    final transport = _FakeTransport();
    final controller = RelayDemoController(
      transport,
      requestDuration: const Duration(milliseconds: 20),
    );
    controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);
    await controller.connectTo(_helperPeer);
    await _waitFor(() => controller.requestState == RelayRequestState.failed);
    expect(controller.isWaitingForAcceptance, isFalse);
    expect(controller.errorMessage, contains('timed out'));
    expect(transport.connection.isClosed, isTrue);
    await _dispose(controller);
  });

  test(
    'duplicate acceptance cannot replace established encryption keys',
    () async {
      final session = await _offlineConnected();
      final request = RelayEnvelope.decode(
        session.transport.connection.sent.first,
      );
      session.transport.connection.emit(
        RelayEnvelope.create(
          type: RelayMessageType.connectionAccept,
          body: {'requestId': request.id},
        ),
      );
      await _flushEvents();
      await session.controller.sendChat('still encrypted');
      expect(session.controller.securityState, RelaySecurityState.ready);
      await _dispose(session.controller);
    },
  );

  test(
    'security exchange has a finite timeout and clears chat state on return',
    () async {
      final transport = _FakeTransport();
      final controller = RelayDemoController(
        transport,
        securityDuration: const Duration(milliseconds: 40),
      );
      controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);
      await controller.connectTo(_helperPeer);
      final request = RelayEnvelope.decode(transport.connection.sent.first);
      transport.connection.emit(
        RelayEnvelope.create(
          type: RelayMessageType.connectionAccept,
          body: {'requestId': request.id},
        ),
      );
      await _waitFor(() => controller.isChatTerminal);
      expect(controller.chatEndReason, RelayChatEndReason.securityFailed);
      await controller.returnToNearby();
      expect(controller.securityState, RelaySecurityState.idle);
      expect(controller.messages, isEmpty);
      expect(controller.isChatTerminal, isFalse);
      await _dispose(controller);
    },
  );
  test(
    'offline user connects, sends a request, and enters chat on accept',
    () async {
      final transport = _FakeTransport();
      final controller = RelayDemoController(transport);
      controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);
      await controller.findNearbyHelpers();
      transport.discoveries.add(_helperPeer);
      await _flushEvents();
      expect(controller.peers, hasLength(1));

      await controller.connectTo(_helperPeer);
      final request = RelayEnvelope.decode(transport.connection.sent.single);
      expect(request.type, RelayMessageType.connectionRequest);
      expect(request.body, {'name': 'Avery', 'role': 'offline_user'});
      expect(controller.isWaitingForAcceptance, isTrue);

      transport.connection.emit(
        RelayEnvelope.create(
          type: RelayMessageType.connectionAccept,
          body: {'requestId': request.id},
        ),
      );
      await _flushEvents();
      expect(controller.inChat, isTrue);
      expect(controller.isWaitingForAcceptance, isFalse);
      expect(controller.securityState, RelaySecurityState.exchangingKeys);
      await _dispose(controller);
    },
  );

  test('helper can accept or reject an incoming request', () async {
    final accepted = await _helperWithRequest();
    final requestId = accepted.request.id;
    await accepted.controller.acceptIncomingRequest();
    final accept = accepted.transport.connection.sent
        .map(RelayEnvelope.decode)
        .firstWhere(
          (envelope) => envelope.type == RelayMessageType.connectionAccept,
        );
    expect(accept.type, RelayMessageType.connectionAccept);
    expect(accept.body['requestId'], requestId);
    expect(accepted.controller.inChat, isTrue);
    await _dispose(accepted.controller);

    final rejected = await _helperWithRequest();
    await rejected.controller.rejectIncomingRequest();
    final reject = RelayEnvelope.decode(
      rejected.transport.connection.sent.single,
    );
    expect(reject.type, RelayMessageType.connectionReject);
    expect(reject.body['requestId'], rejected.request.id);
    expect(rejected.transport.connection.isClosed, isTrue);
    expect(rejected.controller.hasIncomingRequest, isFalse);
    await _dispose(rejected.controller);
  });

  test(
    'chat sends encrypted application data and creates a local message',
    () async {
      final session = await _offlineConnected();
      await session.controller.sendChat('Hello from offline');

      final sent = RelayEnvelope.decode(session.transport.connection.sent.last);
      expect(sent.type, RelayMessageType.secureMessage);
      expect(
        utf8.decode(session.transport.connection.sent.last),
        isNot(contains('Hello from offline')),
      );
      final cleartext = await session.remoteSession.decrypt(
        counter: sent.body['n']! as int,
        ciphertext: sent.body['c']! as String,
      );
      final decoded =
          jsonDecode(utf8.decode(cleartext)) as Map<String, dynamic>;
      expect(decoded['t'], RelayMessageType.chat.wireName);
      expect((decoded['b'] as Map)['text'], 'Hello from offline');
      expect(session.controller.messages.single.text, 'Hello from offline');
      expect(session.controller.messages.single.fromLocalUser, isTrue);
      await _dispose(session.controller);
    },
  );

  test('received chat messages are added to the conversation', () async {
    final session = await _offlineConnected();
    final frame = await session.remoteSession.encrypt(
      utf8.encode(
        jsonEncode({
          't': RelayMessageType.chat.wireName,
          'b': {'text': 'Hello from helper'},
        }),
      ),
    );
    session.transport.connection.emit(
      RelayEnvelope(
        id: 'peer-1',
        type: RelayMessageType.secureMessage,
        body: {'n': frame.counter, 'c': frame.ciphertext},
      ),
    );
    await _waitFor(() => session.controller.messages.isNotEmpty);

    expect(session.controller.messages, hasLength(1));
    expect(session.controller.messages.single.text, 'Hello from helper');
    expect(session.controller.messages.single.fromLocalUser, isFalse);
    await _dispose(session.controller);
  });

  test('helper availability can be restored and explicitly stopped', () async {
    final transport = _FakeTransport();
    final controller = RelayDemoController(transport);
    controller.updateProfile(
      name: 'Helper',
      role: RelayUserRole.internetHelper,
    );
    await controller.offerHelp();
    expect(controller.isOffering, isTrue);

    transport.availability.add(
      const HelperAvailabilityState(enabled: true, displayName: 'Restored'),
    );
    await _flushEvents();
    expect(controller.displayName, 'Restored');
    expect(controller.role, RelayUserRole.internetHelper);
    expect(controller.isOffering, isTrue);

    await controller.stopOfferingHelp();
    expect(transport.stoppedHelperAvailability, isTrue);
    expect(controller.isOffering, isFalse);
    await _dispose(controller);
  });

  test(
    'discovery reports an empty result after its real scan window',
    () async {
      final transport = _FakeTransport();
      final controller = RelayDemoController(
        transport,
        discoveryDuration: const Duration(milliseconds: 10),
      );
      controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);

      await controller.findNearbyHelpers();
      expect(controller.isDiscovering, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isDiscovering, isFalse);
      expect(controller.noPeopleFound, isTrue);
      expect(controller.peers, isEmpty);
      await _dispose(controller);
    },
  );

  test(
    'end chat sends end_chat and distinguishes local from remote ending',
    () async {
      final session = await _offlineConnected();
      await session.controller.endChat();
      final sent = RelayEnvelope.decode(session.transport.connection.sent.last);
      expect(sent.type, RelayMessageType.secureMessage);
      final cleartext = await session.remoteSession.decrypt(
        counter: sent.body['n']! as int,
        ciphertext: sent.body['c']! as String,
      );
      expect((jsonDecode(utf8.decode(cleartext)) as Map)['t'], 'end_chat');
      expect(session.controller.chatEndReason, RelayChatEndReason.local);
      expect(session.controller.isChatTerminal, isTrue);
      await _dispose(session.controller);

      final remoteEnded = await _offlineConnected();
      final frame = await remoteEnded.remoteSession.encrypt(
        utf8.encode(jsonEncode({'t': 'end_chat', 'b': const {}})),
      );
      remoteEnded.transport.connection.emit(
        RelayEnvelope(
          id: 'peer-end',
          type: RelayMessageType.secureMessage,
          body: {'n': frame.counter, 'c': frame.ciphertext},
        ),
      );
      await _waitFor(() => remoteEnded.controller.isChatTerminal);
      expect(remoteEnded.controller.chatEndReason, RelayChatEndReason.remote);
      await _dispose(remoteEnded.controller);
    },
  );

  test(
    'unexpected disconnect produces a connection-lost terminal state',
    () async {
      final session = await _offlineConnected();
      session.transport.connection.endUnexpectedly();
      await _waitFor(() => session.controller.isChatTerminal);
      expect(
        session.controller.chatEndReason,
        RelayChatEndReason.connectionLost,
      );
      await _dispose(session.controller);
    },
  );

  test('reports are stored locally for this chat only', () async {
    final session = await _offlineConnected();
    session.controller.submitLocalReport(
      reason: 'Spam or scam',
      note: 'Repeated unwanted messages',
    );
    expect(session.controller.hasSubmittedReport, isTrue);
    expect(session.controller.submittedReport?.reason, 'Spam or scam');
    expect(
      session.controller.submittedReport?.note,
      'Repeated unwanted messages',
    );
    expect(
      session.transport.connection.sent
          .map(RelayEnvelope.decode)
          .where((envelope) => envelope.type == RelayMessageType.secureMessage),
      hasLength(1), // Only the automatic encrypted key confirmation was sent.
    );
    await session.controller.returnToNearby();
    expect(session.controller.submittedReport, isNull);
    await _dispose(session.controller);
  });

  test('outgoing pending requests can be cancelled explicitly', () async {
    final transport = _FakeTransport();
    final controller = RelayDemoController(transport);
    controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);
    await controller.connectTo(_helperPeer);
    await controller.cancelPendingRequest();
    final cancel = transport.connection.sent.map(RelayEnvelope.decode).last;
    expect(cancel.type, RelayMessageType.connectionCancel);
    expect(controller.requestState, RelayRequestState.cancelled);
    await _dispose(controller);
  });

  test('declined requests are shown as a terminal request result', () async {
    final transport = _FakeTransport();
    final controller = RelayDemoController(transport);
    controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);
    await controller.connectTo(_helperPeer);
    final request = RelayEnvelope.decode(transport.connection.sent.single);
    transport.connection.emit(
      RelayEnvelope.create(
        type: RelayMessageType.connectionReject,
        body: {'requestId': request.id},
      ),
    );
    await _waitFor(() => controller.requestState == RelayRequestState.declined);
    expect(controller.status, contains('declined'));
    expect(controller.inChat, isFalse);
    await _dispose(controller);
  });

  test('helper sees a requester cancellation and remains available', () async {
    final session = await _helperWithRequest();
    session.transport.connection.emit(
      RelayEnvelope.create(
        type: RelayMessageType.connectionCancel,
        body: {'requestId': session.request.id},
      ),
    );
    await _waitFor(() => !session.controller.hasIncomingRequest);
    expect(session.controller.requestState, RelayRequestState.cancelled);
    expect(session.controller.isOffering, isTrue);
    await _dispose(session.controller);
  });

  test(
    'Bluetooth and permission errors are recoverable Nearby states',
    () async {
      for (final (detail, expected) in [
        ('Nearby Devices permission denied', 'Nearby permissions'),
        ('Bluetooth is disabled', 'Turn on Bluetooth'),
        ('Adapter unavailable', 'Adapter unavailable'),
      ]) {
        final transport = _FakeTransport();
        final controller = RelayDemoController(transport);
        controller.updateProfile(
          name: 'Avery',
          role: RelayUserRole.offlineUser,
        );
        await controller.findNearbyHelpers();
        transport.discoveries.addError(StateError(detail));
        await _waitFor(() => controller.errorMessage != null);
        expect(controller.errorMessage, contains(expected));
        expect(controller.isDiscovering, isFalse);
        await _dispose(controller);
      }
    },
  );
}

final _helperPeer = RelayPeer(
  id: 'peer-helper',
  label: 'Helper',
  metadata: {'role': 'internet_helper'},
);

Future<_HelperSession> _helperWithRequest() async {
  final transport = _FakeTransport();
  final controller = RelayDemoController(transport);
  controller.updateProfile(name: 'Helper', role: RelayUserRole.internetHelper);
  await controller.offerHelp();
  transport.incoming.add(transport.connection);
  await _flushEvents();
  const requestId = 'connect-request-1';
  final request = RelayEnvelope(
    id: requestId,
    type: RelayMessageType.connectionRequest,
    body: const {'name': 'Avery', 'role': 'offline_user'},
  );
  transport.connection.emit(request);
  await _flushEvents();
  expect(controller.hasIncomingRequest, isTrue);
  return _HelperSession(controller, transport, request);
}

Future<_OfflineSession> _offlineConnected() async {
  final transport = _FakeTransport();
  final controller = RelayDemoController(transport);
  controller.updateProfile(name: 'Avery', role: RelayUserRole.offlineUser);
  await controller.connectTo(_helperPeer);
  final request = RelayEnvelope.decode(transport.connection.sent.single);
  transport.connection.emit(
    RelayEnvelope.create(
      type: RelayMessageType.connectionAccept,
      body: {'requestId': request.id},
    ),
  );
  await _waitFor(
    () => controller.securityState == RelaySecurityState.exchangingKeys,
  );
  final initiatorKeyExchange = transport.connection.sent
      .map(RelayEnvelope.decode)
      .firstWhere((envelope) => envelope.type == RelayMessageType.keyExchange);
  final remoteSession = await RelaySecureSession.create(isInitiator: false);
  final remotePublicKey = await remoteSession.publicKeyBase64;
  await remoteSession.establish(
    initiatorKeyExchange.body['publicKey']! as String,
  );
  transport.connection.emit(
    RelayEnvelope.create(
      type: RelayMessageType.keyExchange,
      body: {'publicKey': remotePublicKey},
    ),
  );

  final remoteConfirm = await remoteSession.encrypt(
    utf8.encode(
      jsonEncode({
        't': RelayMessageType.keyConfirmation.wireName,
        'b': {'confirm': true},
      }),
    ),
  );
  transport.connection.emit(
    RelayEnvelope(
      id: 'peer-confirm',
      type: RelayMessageType.secureMessage,
      body: {'n': remoteConfirm.counter, 'c': remoteConfirm.ciphertext},
    ),
  );

  await _waitFor(() => controller.securityState == RelaySecurityState.ready);
  expect(controller.inChat, isTrue);
  return _OfflineSession(controller, transport, remoteSession);
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for controller state.');
}

Future<void> _dispose(RelayDemoController controller) async {
  controller.dispose();
  await Future<void>.delayed(Duration.zero);
}

class _HelperSession {
  const _HelperSession(this.controller, this.transport, this.request);
  final RelayDemoController controller;
  final _FakeTransport transport;
  final RelayEnvelope request;
}

class _OfflineSession {
  const _OfflineSession(this.controller, this.transport, this.remoteSession);
  final RelayDemoController controller;
  final _FakeTransport transport;
  final RelaySecureSession remoteSession;
}

class _FakeTransport implements RelayTransport, HelperAvailabilityControl {
  final incoming = StreamController<RelayConnection>.broadcast();
  final discoveries = StreamController<RelayPeer>.broadcast();
  final availability = StreamController<HelperAvailabilityState>.broadcast();
  final accepted = StreamController<HelperAcceptedEvent>.broadcast();
  final connection = _FakeConnection(_helperPeer);
  RelayProfile? advertisedProfile;
  bool stoppedHelperAvailability = false;

  @override
  Stream<RelayConnection> get incomingConnections => incoming.stream;

  @override
  Stream<HelperAvailabilityState> get availabilityStates => availability.stream;

  @override
  Stream<HelperAcceptedEvent> get acceptedConnections => accepted.stream;

  @override
  Stream<RelayPeer> discover() => discoveries.stream;

  @override
  Future<RelayConnection> connect(RelayPeer peer) async => connection;

  @override
  Future<void> advertise(RelayProfile profile) async {
    advertisedProfile = profile;
  }

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> stopHelperAvailability() async {
    stoppedHelperAvailability = true;
  }

  @override
  Future<void> dispose() async {
    await incoming.close();
    await discoveries.close();
    await availability.close();
    await accepted.close();
  }
}

class _FakeConnection implements RelayConnection {
  _FakeConnection(this.peer);

  @override
  final RelayPeer peer;
  final messagesController = StreamController<Uint8List>.broadcast();
  final sent = <Uint8List>[];
  bool isClosed = false;
  bool failNextSend = false;
  bool _sending = false;
  Duration sendDelay = Duration.zero;
  _FakeConnection? deliverTo;

  @override
  int get maxMessageBytes => relayMaxMessageBytes;

  @override
  Stream<Uint8List> get messages => messagesController.stream;

  @override
  Future<void> send(Uint8List message) async {
    if (isClosed || _sending || failNextSend) {
      failNextSend = false;
      throw StateError('Fake transport send unavailable');
    }
    _sending = true;
    deliverTo?.messagesController.add(Uint8List.fromList(message));
    if (sendDelay != Duration.zero) await Future<void>.delayed(sendDelay);
    sent.add(Uint8List.fromList(message));
    _sending = false;
  }

  void emit(RelayEnvelope envelope) {
    messagesController.add(envelope.encode());
  }

  void endUnexpectedly() {
    messagesController.addError(StateError('Connection lost'));
    messagesController.close();
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }
}
