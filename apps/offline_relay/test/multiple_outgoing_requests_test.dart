import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:relay_transport/relay_transport.dart';

final b = RelayPeer(
  id: 'B',
  label: 'Helper B',
  metadata: {'role': 'internet_helper'},
);
final c = RelayPeer(
  id: 'C',
  label: 'Helper C',
  metadata: {'role': 'internet_helper'},
);
final d = RelayPeer(
  id: 'D',
  label: 'Helper D',
  metadata: {'role': 'internet_helper'},
);
Future<void> flush() => Future<void>.delayed(Duration.zero);

class Link implements RelayConnection {
  Link(this.peer);
  @override
  final RelayPeer peer;
  final events = StreamController<Uint8List>.broadcast(sync: true);
  final sent = <RelayEnvelope>[];
  bool closed = false;
  @override
  int get maxMessageBytes => relayMaxMessageBytes;
  @override
  Stream<Uint8List> get messages => events.stream;
  @override
  Future<void> send(Uint8List bytes) async {
    sent.add(RelayEnvelope.decode(bytes));
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  void reply(RelayMessageType type, {String? requestId}) => events.add(
    RelayEnvelope.create(
      type: type,
      body: {'requestId': requestId ?? sent.first.id},
    ).encode(),
  );
  void chat(String text) => events.add(
    RelayEnvelope.create(
      type: RelayMessageType.chat,
      body: {'text': text},
    ).encode(),
  );
}

class Transport implements RelayTransport {
  final links = <String, Link>{};
  final delayed = <String, Completer<RelayConnection>>{};
  final discoveries = StreamController<RelayPeer>.broadcast();
  final incoming = StreamController<RelayConnection>.broadcast();
  bool discoveryCancelled = false;
  @override
  Stream<RelayConnection> get incomingConnections => incoming.stream;
  @override
  Stream<RelayPeer> discover() {
    discoveryCancelled = false;
    return discoveries.stream
        .transform(StreamTransformer<RelayPeer, RelayPeer>.fromHandlers())
        .asBroadcastStream(
          onCancel: (subscription) {
            discoveryCancelled = true;
            subscription.cancel();
          },
        );
  }

  @override
  Future<RelayConnection> connect(RelayPeer peer) async {
    final link = links.putIfAbsent(peer.id, () => Link(peer));
    return delayed[peer.id]?.future ?? link;
  }

  @override
  Future<void> advertise(RelayProfile profile) async {}
  @override
  Future<void> stopAdvertising() async {}
  @override
  Future<void> dispose() async {
    for (final link in links.values) {
      await link.events.close();
    }
    await discoveries.close();
    await incoming.close();
  }
}

void main() {
  late Transport transport;
  late RelayDemoController controller;
  setUp(() async {
    transport = Transport();
    controller = RelayDemoController(transport);
    controller.updateProfile(name: 'A', role: RelayUserRole.offlineUser);
    await controller.findNearbyHelpers();
    transport.discoveries.add(b);
    transport.discoveries.add(c);
    await flush();
  });
  tearDown(() async {
    controller.dispose();
    await flush();
  });

  Future<void> requestBoth() async {
    await controller.connectTo(b);
    await controller.connectTo(c);
    expect(transport.links['B']!.closed, isFalse);
    expect(controller.isRequesting(b), isTrue);
    expect(controller.isRequesting(c), isTrue);
    expect(controller.isDiscovering, isTrue);
    expect(controller.peers, hasLength(2));
    expect(
      transport.links['B']!.sent.first.id,
      isNot(transport.links['C']!.sent.first.id),
    );
  }

  test('request B then C retains B and discovery; duplicate tap does not reconnect', () async {
    await requestBoth();
    await controller.connectTo(b);
    expect(transport.links['B']!.sent, hasLength(1));
    expect(transport.discoveryCancelled, isFalse);
  });
  test('B rejects while C remains pending and D can be requested', () async {
    await requestBoth();
    transport.links['B']!.reply(RelayMessageType.connectionReject);
    await flush();
    expect(controller.isRequesting(b), isFalse);
    expect(controller.isRequesting(c), isTrue);
    expect(transport.links['B']!.closed, isTrue);
    await controller.connectTo(d);
    expect(controller.isRequesting(d), isTrue);
  });
  test('B disconnects while C remains pending', () async {
    await requestBoth();
    await transport.links['B']!.events.close();
    await flush();
    expect(controller.isRequesting(b), isFalse);
    expect(controller.isRequesting(c), isTrue);
    transport.links['C']!.reply(RelayMessageType.connectionAccept);
    expect(controller.selectedPeerId, 'C');
  });
  test('C wins, closes B, ignores late accepts and losing chat; winner chats normally', () async {
    await requestBoth();
    transport.links['B']!.chat('not accepted');
    expect(controller.messages, isEmpty);
    transport.links['C']!.reply(RelayMessageType.connectionAccept);
    transport.links['B']!.reply(RelayMessageType.connectionAccept);
    transport.links['B']!.chat('loser injection');
    await flush();
    expect(controller.inChat, isTrue);
    expect(controller.selectedPeerId, 'C');
    expect(controller.remoteName, 'Helper C');
    expect(transport.links['B']!.closed, isTrue);
    expect(controller.isWaitingForAcceptance, isFalse);
    expect(controller.messages, isEmpty);
    await controller.sendChat('to winner');
    transport.links['C']!.chat('from winner');
    expect(transport.links['C']!.sent.last.body['text'], 'to winner');
    expect(transport.links['B']!.sent, hasLength(1));
    expect(controller.messages.map((message) => message.text), [
      'to winner',
      'from winner',
    ]);
    await controller.returnToNearby();
    expect(transport.links['C']!.closed, isTrue);
    expect(controller.inChat, isFalse);
    expect(controller.selectedPeerId, isNull);
    expect(controller.messages, isEmpty);
  });
  test('near simultaneous accepts select exactly the first winner', () async {
    await requestBoth();
    transport.links['B']!.reply(RelayMessageType.connectionAccept);
    transport.links['C']!.reply(RelayMessageType.connectionAccept);
    await flush();
    expect(controller.selectedPeerId, 'B');
    expect(transport.links['B']!.closed, isFalse);
    expect(transport.links['C']!.closed, isTrue);
  });
  test('winner disconnect ends only the selected chat', () async {
    await requestBoth();
    transport.links['C']!.reply(RelayMessageType.connectionAccept);
    await transport.links['C']!.events.close();
    await flush();
    expect(controller.inChat, isFalse);
    expect(controller.selectedPeerId, isNull);
    expect(controller.isWaitingForAcceptance, isFalse);
  });
  test(
    'wrong request correlation cannot select or reject a pending connection',
    () async {
      await requestBoth();
      transport.links['B']!.reply(
        RelayMessageType.connectionAccept,
        requestId: transport.links['C']!.sent.first.id,
      );
      transport.links['B']!.reply(
        RelayMessageType.connectionReject,
        requestId: 'wrong',
      );
      expect(controller.inChat, isFalse);
      expect(controller.isRequesting(b), isTrue);
    },
  );
  test(
    'winner invalidates an in-flight connect and closes its late completion',
    () async {
      transport.delayed['B'] = Completer<RelayConnection>();
      final connecting = controller.connectTo(b);
      await flush();
      await controller.connectTo(c);
      transport.links['C']!.reply(RelayMessageType.connectionAccept);
      transport.delayed['B']!.complete(transport.links['B']!);
      await connecting;
      expect(transport.links['B']!.closed, isTrue);
      expect(transport.links['B']!.sent, isEmpty);
      expect(controller.selectedPeerId, 'C');
    },
  );
  test(
    'return to Nearby closes all pending and ignores late connect results',
    () async {
      await controller.connectTo(c);
      transport.delayed['B'] = Completer<RelayConnection>();
      final connecting = controller.connectTo(b);
      await flush();
      await controller.returnToNearby();
      transport.delayed['B']!.complete(transport.links['B']!);
      await connecting;
      expect(transport.links.values.every((link) => link.closed), isTrue);
      expect(controller.isWaitingForAcceptance, isFalse);
      expect(controller.isConnecting, isFalse);
    },
  );
  test('one connect failure leaves other pending requests active', () async {
    await controller.connectTo(c);
    transport.delayed['B'] = Completer<RelayConnection>();
    final connecting = controller.connectTo(b);
    await flush();
    transport.delayed['B']!.completeError(StateError('cannot connect'));
    await connecting;
    expect(controller.isRequesting(c), isTrue);
    expect(controller.isRequesting(b), isFalse);
  });
}
