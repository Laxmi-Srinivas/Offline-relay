import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/transport/ble_relay_transport.dart';
import 'package:relay_transport/relay_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('dev.offlinerelay/ble/methods');
  const events = MethodChannel('dev.offlinerelay/ble/events');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final peer = <String, Object>{
    'id': 'helper-id',
    'label': 'Helper',
    'metadata': {'role': 'internet_helper'},
  };

  Future<void> emit(Map<String, Object> event) async {
    // Inject the exact native EventChannel shape into the shared Dart adapter.
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
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'connect') {
        return {'connectionId': 'link-1', 'peer': peer};
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(methods, null);
  });

  test(
    'native discovery, connect, bytes, ACK completion, close contract',
    () async {
      final transport = BleRelayTransport();
      final found = <RelayPeer>[];
      final discovery = transport.discover().listen(found.add);
      await Future<void>.delayed(Duration.zero);
      await emit({'event': 'peerDiscovered', 'peer': peer});
      expect(found.single.metadata['role'], 'internet_helper');
      final connection = await transport.connect(found.single);
      expect(calls.last.arguments, {'peerId': 'helper-id'});
      final received = <Uint8List>[];
      final messages = connection.messages.listen(received.add);
      final bytes = RelayEnvelope.create(
        type: RelayMessageType.chat,
        body: {'text': 'Hi 🌍'},
      ).encode();
      await connection.send(bytes);
      expect(calls.last.arguments, {
        'connectionId': 'link-1',
        'message': bytes,
      });
      await emit({
        'event': 'message',
        'connectionId': 'link-1',
        'message': bytes,
      });
      expect(received.single, bytes);
      await discovery.cancel();
      await connection.close();
      expect(
        calls.map((c) => c.method),
        containsAllInOrder([
          'startDiscovery',
          'connect',
          'send',
          'stopDiscovery',
          'close',
        ]),
      );
      await messages.cancel();
      await transport.dispose();
      expect(calls.last.method, 'dispose');
    },
  );

  test(
    'profile, incoming connection, disconnect, stop advertising contract',
    () async {
      final transport = BleRelayTransport();
      await transport.advertise(
        RelayProfile(
          id: 'local',
          label: 'Helper',
          metadata: {'role': 'internet_helper'},
        ),
      );
      expect(calls.last.arguments, {
        'profile': {
          'id': 'local',
          'label': 'Helper',
          'metadata': {'role': 'internet_helper'},
        },
      });
      final incoming = Completer<RelayConnection>();
      final subscription = transport.incomingConnections.listen(
        incoming.complete,
      );
      await emit({
        'event': 'incomingConnection',
        'connectionId': 'incoming-1',
        'peer': peer,
      });
      final connection = await incoming.future;
      final errors = <Object>[];
      final messages = connection.messages.listen((_) {}, onError: errors.add);
      await emit({
        'event': 'disconnected',
        'connectionId': 'incoming-1',
        'reason': 'Peer unsubscribed',
      });
      expect(errors.single.toString(), contains('Peer unsubscribed'));
      await transport.stopAdvertising();
      expect(calls.last.method, 'stopAdvertising');
      await messages.cancel();
      await subscription.cancel();
      await transport.dispose();
    },
  );

  test(
    'native discovery errors propagate and sessionEnded is accepted',
    () async {
      final transport = BleRelayTransport();
      final errors = <Object>[];
      final discovery = transport.discover().listen(
        (_) {},
        onError: errors.add,
      );
      await Future<void>.delayed(Duration.zero);
      await emit({
        'event': 'error',
        'message': 'Bluetooth permission is required',
      });
      await emit({
        'event': 'sessionEnded',
        'reason': 'Bluetooth permission is required',
      });
      expect(
        errors.single.toString(),
        contains('Bluetooth permission is required'),
      );
      await discovery.cancel();
      await transport.dispose();
    },
  );
}
