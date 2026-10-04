import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:relay_transport/relay_transport.dart';

import 'package:offline_relay/transport/helper_availability.dart';

void main() {
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
      await _dispose(controller);
    },
  );

  test('helper can accept or reject an incoming request', () async {
    final accepted = await _helperWithRequest();
    final requestId = accepted.request.id;
    await accepted.controller.acceptIncomingRequest();
    final accept = RelayEnvelope.decode(
      accepted.transport.connection.sent.single,
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
    'chat send creates a local message and transmits a chat envelope',
    () async {
      final session = await _offlineConnected();
      await session.controller.sendChat('Hello from offline');

      final sent = RelayEnvelope.decode(session.transport.connection.sent.last);
      expect(sent.type, RelayMessageType.chat);
      expect(sent.body['text'], 'Hello from offline');
      expect(session.controller.messages.single.text, 'Hello from offline');
      expect(session.controller.messages.single.fromLocalUser, isTrue);
      await _dispose(session.controller);
    },
  );

  test('received chat messages are added to the conversation', () async {
    final session = await _offlineConnected();
    session.transport.connection.emit(
      RelayEnvelope.create(
        type: RelayMessageType.chat,
        body: {'text': 'Hello from helper'},
      ),
    );
    await _flushEvents();

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
  await _flushEvents();
  expect(controller.inChat, isTrue);
  return _OfflineSession(controller, transport);
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

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
  const _OfflineSession(this.controller, this.transport);
  final RelayDemoController controller;
  final _FakeTransport transport;
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

  @override
  int get maxMessageBytes => relayMaxMessageBytes;

  @override
  Stream<Uint8List> get messages => messagesController.stream;

  @override
  Future<void> send(Uint8List message) async {
    sent.add(Uint8List.fromList(message));
  }

  void emit(RelayEnvelope envelope) {
    messagesController.add(envelope.encode());
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }
}
