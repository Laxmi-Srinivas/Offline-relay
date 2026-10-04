import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/security/relay_secure_session.dart';
import 'package:offline_relay/transport/ble_relay_transport.dart';
import 'package:relay_transport/relay_transport.dart';

// Exercises the existing shared bridge with the iOS native channel map contract.
// Mocked native callbacks are not CoreBluetooth or physical-device validation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('dev.offlinerelay/ble/methods');
  const events = MethodChannel('dev.offlinerelay/ble/events');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final peer = <String, Object>{
    'id': 'corebluetooth-device-id',
    'label': 'Helper',
    'metadata': {'role': 'internet_helper'},
  };
  Completer<void>? nativeSend;

  Future<void> emit(Map<String, Object> event) async {
    // ignore: deprecated_member_use
    await messenger.handlePlatformMessage(
      events.name,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    calls.clear();
    nativeSend = null;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'connect') {
        return {'connectionId': 'ios-central-link', 'peer': peer};
      }
      if (call.method == 'send') await nativeSend?.future;
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(methods, null);
  });

  test('iOS channel carries current encrypted chat and End Chat unchanged', () async {
    final transport = BleRelayTransport();
    final found = <RelayPeer>[];
    final discovery = transport.discover().listen(found.add);
    await Future<void>.delayed(Duration.zero);
    await emit({'event': 'peerDiscovered', 'peer': peer});
    expect(found.single.metadata['role'], 'internet_helper');
    // Match the current controller: discovery may end before the user connects.
    await discovery.cancel();
    final connection = await transport.connect(found.single);
    expect(connection.maxMessageBytes, 256);
    final received = <Uint8List>[];
    final messages = connection.messages.listen(received.add);
    final requester = await RelaySecureSession.create(isInitiator: true);
    final helper = await RelaySecureSession.create(isInitiator: false);
    final requesterKey = await requester.publicKeyBase64;
    final helperKey = await helper.publicKeyBase64;
    await requester.establish(helperKey);
    await helper.establish(requesterKey);

    for (final type in [
      RelayMessageType.keyConfirmation,
      RelayMessageType.chat,
      RelayMessageType.endChat,
    ]) {
      final cleartext = utf8.encode(
        jsonEncode({
          't': type.wireName,
          'b': type == RelayMessageType.chat
              ? {'text': 'Hi 🌍'}
              : type == RelayMessageType.keyConfirmation
              ? {'confirm': true}
              : <String, Object>{},
        }),
      );
      final encrypted = await requester.encrypt(cleartext);
      final envelope = RelayEnvelope(
        id: 's${encrypted.counter.toRadixString(36)}',
        type: RelayMessageType.secureMessage,
        body: {'n': encrypted.counter, 'c': encrypted.ciphertext},
      );
      final bytes = envelope.encode();
      expect(bytes.length, lessThanOrEqualTo(256));
      expect(utf8.decode(bytes), isNot(contains('Hi 🌍')));
      nativeSend = Completer<void>();
      var completed = false;
      final send = connection.send(bytes).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(calls.last.arguments, {
        'connectionId': 'ios-central-link',
        'message': bytes,
      });
      // Native completion represents the exact matching transport ACK.
      nativeSend!.complete();
      await send;
      expect(
        await helper.decrypt(
          counter: encrypted.counter,
          ciphertext: encrypted.ciphertext,
        ),
        cleartext,
      );
      final reply = await helper.encrypt(cleartext);
      final replyBytes = RelayEnvelope(
        id: 's${reply.counter.toRadixString(36)}',
        type: RelayMessageType.secureMessage,
        body: {'n': reply.counter, 'c': reply.ciphertext},
      ).encode();
      await emit({
        'event': 'message',
        'connectionId': 'ios-central-link',
        'message': replyBytes,
      });
      expect(received.last, replyBytes);
      final decoded = RelayEnvelope.decode(received.last);
      expect(
        await requester.decrypt(
          counter: decoded.body['n']! as int,
          ciphertext: decoded.body['c']! as String,
        ),
        cleartext,
      );
    }
    await connection.close();
    await messages.cancel();
    requester.close();
    helper.close();
    await transport.dispose();
    expect(
      calls.map((call) => call.method),
      containsAllInOrder([
        'startDiscovery',
        'stopDiscovery',
        'connect',
        'send',
        'close',
        'dispose',
      ]),
    );
  });

  test(
    'iOS disconnect terminates the shared connection and rejects later sends',
    () async {
      final transport = BleRelayTransport();
      final connection = await transport.connect(
        RelayPeer(id: 'corebluetooth-device-id', label: 'Helper'),
      );
      final errors = <Object>[];
      final subscription = connection.messages.listen(
        (_) {},
        onError: errors.add,
      );
      await emit({
        'event': 'disconnected',
        'connectionId': 'ios-central-link',
        'reason': 'Peer disconnected',
      });
      expect(errors.single.toString(), contains('Peer disconnected'));
      await expectLater(
        connection.send(Uint8List.fromList([1])),
        throwsStateError,
      );
      await subscription.cancel();
      await transport.dispose();
    },
  );
}
