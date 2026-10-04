import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:relay_transport/relay_transport.dart';

void main() {
  late TestTransport transport;
  late RelayDemoController controller;

  setUp(() {
    transport = TestTransport();
    controller = RelayDemoController(transport);
  });

  tearDown(() async {
    controller.dispose();
    await flush();
  });

  Future<TestConnection> incoming() async {
    controller.updateProfile(
      name: 'Helper',
      role: RelayUserRole.internetHelper,
    );
    await controller.offerHelp();
    final connection = TestConnection('incoming');
    transport.incoming.add(connection);
    await flush();
    return connection;
  }

  Future<TestConnection> outgoing({bool accept = true}) async {
    controller.updateProfile(name: 'User', role: RelayUserRole.offlineUser);
    final connection = transport.nextConnection;
    await controller.connectTo(connection.peer);
    if (accept) {
      final request = RelayEnvelope.decode(connection.sent.single);
      connection.emit(RelayMessageType.connectionAccept, {
        'requestId': request.id,
      });
      await flush();
    }
    return connection;
  }

  test('missing request ID cannot bypass helper approval', () async {
    final connection = await incoming();
    connection.emit(RelayMessageType.connectionAccept, {});
    await flush();
    expect(controller.inChat, isFalse);
    expect(controller.messages, isEmpty);
  });

  testWidgets('subscribed peer without a request expires and frees the slot', (
    tester,
  ) async {
    controller.dispose();
    transport = TestTransport();
    controller = RelayDemoController(transport);
    controller.updateProfile(
      name: 'Helper',
      role: RelayUserRole.internetHelper,
    );
    await controller.offerHelp();
    final idle = TestConnection('idle');
    transport.incoming.add(idle);
    await tester.pump();
    await tester.pump(const Duration(seconds: 14));
    expect(idle.closed, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(idle.closed, isTrue);
    expect(controller.hasIncomingRequest, isFalse);
    await controller.offerHelp();
    final next = TestConnection('next');
    transport.incoming.add(next);
    await tester.pump();
    next.emit(RelayMessageType.connectionRequest, {
      'name': 'Next',
      'role': 'offline_user',
    });
    await tester.pump();
    expect(controller.hasIncomingRequest, isTrue);
    expect(next.closed, isFalse);
  });

  testWidgets('valid request cancels setup timer while user decides', (
    tester,
  ) async {
    controller.dispose();
    transport = TestTransport();
    controller = RelayDemoController(transport);
    controller.updateProfile(
      name: 'Helper',
      role: RelayUserRole.internetHelper,
    );
    await controller.offerHelp();
    final peer = TestConnection('request');
    transport.incoming.add(peer);
    await tester.pump();
    peer.emit(RelayMessageType.connectionRequest, {
      'name': 'User',
      'role': 'offline_user',
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(peer.closed, isFalse);
    expect(controller.hasIncomingRequest, isTrue);
  });

  test('chat is ignored until helper approval', () async {
    final connection = await incoming();
    connection.emit(RelayMessageType.chat, {'text': 'unsolicited'});
    connection.emit(RelayMessageType.connectionRequest, {
      'name': 'User',
      'role': 'offline_user',
    });
    await flush();
    expect(controller.messages, isEmpty);
    await controller.acceptIncomingRequest();
    expect(controller.inChat, isTrue);
    connection.emit(RelayMessageType.chat, {'text': 'approved'});
    await flush();
    expect(controller.messages.single.text, 'approved');
  });

  test('outgoing chat cannot be sent before acceptance', () async {
    final connection = await outgoing(accept: false);
    await expectLater(controller.sendChat('too soon'), throwsStateError);
    expect(connection.sent, hasLength(1));
    expect(controller.messages, isEmpty);
  });

  test('duplicate control messages cannot end an accepted chat', () async {
    final connection = await outgoing();
    final request = RelayEnvelope.decode(connection.sent.first);
    connection.emit(RelayMessageType.connectionReject, {
      'requestId': request.id,
    });
    await flush();
    expect(controller.inChat, isTrue);
    expect(connection.closed, isFalse);
  });

  test('repeated requests cannot change the peer awaiting approval', () async {
    final connection = await incoming();
    connection.emit(RelayMessageType.connectionRequest, {
      'name': 'First',
      'role': 'offline_user',
    }, id: 'first');
    await flush();
    connection.emit(RelayMessageType.connectionRequest, {
      'name': 'Changed',
      'role': 'offline_user',
    }, id: 'second');
    await flush();
    expect(controller.incomingRequestId, 'first');
    expect(controller.incomingPeerName, 'First');
  });

  test('disconnect clears chat state before another conversation', () async {
    final old = await outgoing();
    old.emit(RelayMessageType.chat, {'text': 'old conversation'});
    await flush();
    expect(controller.messages, hasLength(1));
    await old.inbox.close();
    await flush();
    expect(controller.messages, isEmpty);
    expect(controller.remoteName, isNull);
    expect(controller.inChat, isFalse);
    transport.nextConnection = TestConnection('new');
    await outgoing();
    expect(controller.inChat, isTrue);
    expect(controller.messages, isEmpty);
  });

  test('a disconnected incoming peer does not block the next peer', () async {
    final old = await incoming();
    await old.inbox.close();
    await flush();
    final next = await incoming();
    next.emit(RelayMessageType.connectionRequest, {
      'name': 'Next',
      'role': 'offline_user',
    });
    await flush();
    expect(controller.hasIncomingRequest, isTrue);
    expect(next.closed, isFalse);
  });

  test(
    'send completion after leaving chat cannot repopulate history',
    () async {
      final connection = await outgoing();
      final completion = Completer<void>();
      connection.sendCompletion = completion;
      final send = controller.sendChat('pending');
      await controller.returnToNearby();
      completion.complete();
      await send;
      expect(controller.inChat, isFalse);
      expect(controller.messages, isEmpty);
    },
  );

  test('accept completion after leaving chat cannot restore chat', () async {
    final connection = await incoming();
    connection.emit(RelayMessageType.connectionRequest, {
      'name': 'User',
      'role': 'offline_user',
    });
    await flush();
    final completion = Completer<void>();
    connection.sendCompletion = completion;
    final accept = controller.acceptIncomingRequest();
    await flush();
    await controller.returnToNearby();
    completion.complete();
    await accept;
    expect(controller.inChat, isFalse);
    expect(controller.remoteName, isNull);
  });

  test(
    'connect completion after leaving cannot install a stale session',
    () async {
      controller.updateProfile(name: 'User', role: RelayUserRole.offlineUser);
      final completion = Completer<RelayConnection>();
      transport.connectCompletion = completion;
      final connect = controller.connectTo(transport.nextConnection.peer);
      await controller.returnToNearby();
      completion.complete(transport.nextConnection);
      await connect;
      expect(controller.inChat, isFalse);
      expect(controller.isWaitingForAcceptance, isFalse);
      expect(transport.nextConnection.closed, isTrue);
      expect(transport.nextConnection.sent, isEmpty);
    },
  );
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

class TestTransport implements RelayTransport {
  final incoming = StreamController<RelayConnection>.broadcast();
  TestConnection nextConnection = TestConnection('outgoing');
  Completer<RelayConnection>? connectCompletion;

  @override
  Stream<RelayConnection> get incomingConnections => incoming.stream;
  @override
  Stream<RelayPeer> discover() => const Stream.empty();
  @override
  Future<RelayConnection> connect(RelayPeer peer) async =>
      connectCompletion == null
      ? nextConnection
      : await connectCompletion!.future;
  @override
  Future<void> advertise(RelayProfile profile) async {}
  @override
  Future<void> stopAdvertising() async {}
  @override
  Future<void> dispose() => incoming.close();
}

class TestConnection implements RelayConnection {
  TestConnection(String id)
    : peer = RelayPeer(
        id: id,
        label: id,
        metadata: {'role': 'internet_helper'},
      );
  @override
  final RelayPeer peer;
  final inbox = StreamController<Uint8List>.broadcast();
  final sent = <Uint8List>[];
  bool closed = false;
  Completer<void>? sendCompletion;

  @override
  int get maxMessageBytes => relayMaxMessageBytes;
  @override
  Stream<Uint8List> get messages => inbox.stream;
  @override
  Future<void> send(Uint8List bytes) async {
    if (closed) throw StateError('closed');
    sent.add(bytes);
    await sendCompletion?.future;
  }

  void emit(RelayMessageType type, Map<String, Object?> body, {String? id}) {
    inbox.add(
      (id == null
              ? RelayEnvelope.create(type: type, body: body)
              : RelayEnvelope(id: id, type: type, body: body))
          .encode(),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
