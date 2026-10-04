import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:offline_relay/security/relay_secure_session.dart';
import 'package:relay_transport/relay_transport.dart';

void main() {
  test('encrypted incoming history retains newest 300 messages', () async {
    final f = await SecureFixture.connect();
    try {
      for (var i = 0; i < 310; i++) {
        await f.receive('message-$i');
      }
      expect(f.controller.messages.length, 300);
      expect(f.controller.messages.first.text, 'message-10');
      expect(f.controller.messages.last.text, 'message-309');
    } finally {
      f.dispose();
    }
  });
  test('local encrypted sends use the same history bound', () async {
    final f = await SecureFixture.connect();
    try {
      for (var i = 0; i < 310; i++) {
        await f.controller.sendChat('local-$i');
      }
      expect(f.controller.messages.length, 300);
      expect(f.controller.messages.first.text, 'local-10');
    } finally {
      f.dispose();
    }
  });
  test('plaintext chat cannot bypass approval or encryption', () async {
    final t = TestTransport();
    final c = RelayDemoController(t);
    c.updateProfile(name: 'User', role: RelayUserRole.offlineUser);
    await c.connectTo(t.nextConnection.peer);
    t.nextConnection.emit(RelayMessageType.chat, {'text': 'unapproved'});
    t.nextConnection.emit(RelayMessageType.connectionAccept, {});
    await flush();
    expect(c.inChat, false);
    expect(c.messages, isEmpty);
    c.dispose();
    final f = await SecureFixture.connect();
    f.connection.emit(RelayMessageType.chat, {'text': 'plaintext'});
    await flush();
    expect(f.controller.messages, isEmpty);
    f.dispose();
  });
  test(
    'tampered encrypted chat is never displayed and closes the session',
    () async {
      final f = await SecureFixture.connect();
      final e = await f.encrypted('synthetic marker');
      final bytes = base64Url.decode(
        base64Url.normalize(e.body['c'] as String),
      );
      bytes[0] ^= 1;
      f.connection.inbox.add(
        RelayEnvelope(
          id: e.id,
          type: e.type,
          body: {'n': e.body['n'], 'c': base64Url.encode(bytes)},
        ).encode(),
      );
      await waitFor(() => f.controller.isChatTerminal);
      expect(f.controller.messages, isEmpty);
      expect(f.controller.chatEndReason, RelayChatEndReason.securityFailed);
      f.dispose();
    },
  );
  test('replayed encrypted packet is not displayed twice', () async {
    final f = await SecureFixture.connect();
    final e = await f.encrypted('once');
    f.connection.inbox.add(e.encode());
    await waitFor(() => f.controller.messages.length == 1);
    f.connection.inbox.add(e.encode());
    await waitFor(() => f.controller.isChatTerminal);
    expect(f.controller.messages.map((m) => m.text), ['once']);
    f.dispose();
  });
  test(
    'receive work overflow closes the offending connection and recovers',
    () async {
      final f = await SecureFixture.connect();
      for (var i = 0; i < 100; i++) {
        f.connection.emit(RelayMessageType.chat, {'text': 'not encrypted'});
      }
      await flush();
      expect(f.connection.closed, true);
      expect(f.controller.inChat, false);
      await f.controller.returnToNearby();
      expect(f.controller.messages, isEmpty);
      expect(f.controller.isChatTerminal, false);
      f.dispose();
    },
  );
  test('late connect after leaving cannot install an old session', () async {
    final t = TestTransport();
    final done = Completer<RelayConnection>();
    t.connectCompletion = done;
    final c = RelayDemoController(t);
    c.updateProfile(name: 'User', role: RelayUserRole.offlineUser);
    final connecting = c.connectTo(t.nextConnection.peer);
    await c.returnToNearby();
    done.complete(t.nextConnection);
    await connecting;
    expect(t.nextConnection.closed, true);
    expect(t.nextConnection.sent, isEmpty);
    expect(c.isWaitingForAcceptance, false);
    c.dispose();
  });
  test(
    'late acceptance completion cannot revive a departed conversation',
    () async {
      final t = TestTransport();
      final c = RelayDemoController(t);
      c.updateProfile(name: 'Helper', role: RelayUserRole.internetHelper);
      await c.offerHelp();
      final peer = TestConnection('incoming');
      t.incoming.add(peer);
      await flush();
      peer.emit(RelayMessageType.connectionRequest, {
        'name': 'User',
        'role': 'offline_user',
      });
      await flush();
      final blocked = Completer<void>();
      t.stopAdvertisingCompletion = blocked;
      final accepting = c.acceptIncomingRequest();
      await flush();
      await c.returnToNearby();
      blocked.complete();
      await accepting;
      expect(c.inChat, false);
      expect(c.remoteName, isNull);
      c.dispose();
    },
  );
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Expected security state did not arrive');
}

class TestTransport implements RelayTransport {
  final incoming = StreamController<RelayConnection>.broadcast();
  TestConnection nextConnection = TestConnection('outgoing');
  Completer<RelayConnection>? connectCompletion;
  Completer<void>? stopAdvertisingCompletion;
  bool _blockStopOnce = true;
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
  Future<void> stopAdvertising() async {
    if (_blockStopOnce && stopAdvertisingCompletion != null) {
      _blockStopOnce = false;
      await stopAdvertisingCompletion!.future;
    }
  }

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
  final inbox = StreamController<Uint8List>.broadcast(sync: true);
  final sent = <Uint8List>[];
  bool closed = false;
  @override
  int get maxMessageBytes => relayMaxMessageBytes;
  @override
  Stream<Uint8List> get messages => inbox.stream;
  @override
  Future<void> send(Uint8List bytes) async {
    if (closed) throw StateError('closed');
    sent.add(bytes);
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

class SecureFixture {
  SecureFixture(this.controller, this.transport, this.remote);
  final RelayDemoController controller;
  final TestTransport transport;
  final RelaySecureSession remote;
  TestConnection get connection => transport.nextConnection;
  static Future<SecureFixture> connect() async {
    final t = TestTransport();
    final c = RelayDemoController(t);
    c.updateProfile(name: 'Requester', role: RelayUserRole.offlineUser);
    await c.connectTo(t.nextConnection.peer);
    final request = RelayEnvelope.decode(t.nextConnection.sent.single);
    t.nextConnection.emit(RelayMessageType.connectionAccept, {
      'requestId': request.id,
    });
    await waitFor(() => t.nextConnection.sent.length >= 2);
    final key = t.nextConnection.sent
        .map(RelayEnvelope.decode)
        .firstWhere((e) => e.type == RelayMessageType.keyExchange);
    final remote = await RelaySecureSession.create(isInitiator: false);
    final publicKey = await remote.publicKeyBase64;
    await remote.establish(key.body['publicKey'] as String);
    t.nextConnection.emit(RelayMessageType.keyExchange, {
      'publicKey': publicKey,
    });
    final frame = await remote.encrypt(
      utf8.encode(
        jsonEncode({
          't': 'key_confirmation',
          'b': {'confirm': true},
        }),
      ),
    );
    t.nextConnection.emit(RelayMessageType.secureMessage, {
      'n': frame.counter,
      'c': frame.ciphertext,
    });
    await waitFor(() => c.securityState == RelaySecurityState.ready);
    return SecureFixture(c, t, remote);
  }

  Future<RelayEnvelope> encrypted(String text) async {
    final frame = await remote.encrypt(
      utf8.encode(
        jsonEncode({
          't': 'chat',
          'b': {'text': text},
        }),
      ),
    );
    return RelayEnvelope(
      id: 'r${frame.counter}',
      type: RelayMessageType.secureMessage,
      body: {'n': frame.counter, 'c': frame.ciphertext},
    );
  }

  Future<void> receive(String text) async {
    final previous = controller.messages.lastOrNull?.text;
    connection.inbox.add((await encrypted(text)).encode());
    await waitFor(() => controller.messages.lastOrNull?.text != previous);
  }

  void dispose() {
    remote.close();
    controller.dispose();
  }
}
