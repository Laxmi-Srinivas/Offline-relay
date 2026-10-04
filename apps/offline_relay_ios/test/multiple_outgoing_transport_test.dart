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
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'connect') {
        final id = (call.arguments as Map)['peerId'];
        return {
          'connectionId': 'link-$id',
          'peer': {
            'id': id,
            'label': id,
            'metadata': {'role': 'internet_helper'},
          },
        };
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });
  test(
    'scoped link failure preserves discovery and other connection routing',
    () async {
      final transport = BleRelayTransport();
      final discovered = <String>[];
      final discovery = transport.discover().listen(
        (peer) => discovered.add(peer.id),
      );
      await Future<void>.delayed(Duration.zero);
      final b = await transport.connect(RelayPeer(id: 'B', label: 'B'));
      final c = await transport.connect(RelayPeer(id: 'C', label: 'C'));
      final errors = <Object>[];
      final received = <String>[];
      final bMessages = b.messages.listen(
        (_) {},
        onError: (Object error) => errors.add(error),
      );
      final cMessages = c.messages.listen(
        (bytes) =>
            received.add(RelayEnvelope.decode(bytes).body['text'] as String),
      );
      await emit({
        'event': 'error',
        'connectionId': 'link-B',
        'message': 'B ACK timeout',
      });
      await emit({
        'event': 'disconnected',
        'connectionId': 'link-B',
        'reason': 'closed',
      });
      await emit({
        'event': 'peerDiscovered',
        'peer': {'id': 'D', 'label': 'D'},
      });
      await emit({
        'event': 'message',
        'connectionId': 'link-C',
        'message': RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'C survives'},
        ).encode(),
      });
      expect(errors, hasLength(1));
      expect(discovered, ['D']);
      expect(received, ['C survives']);
      await c.send(
        RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'reply'},
        ).encode(),
      );
      expect((calls.last.arguments as Map)['connectionId'], 'link-C');
      await c.close();
      expect((calls.last.arguments as Map)['connectionId'], 'link-C');
      await discovery.cancel();
      expect(calls.last.method, 'stopDiscovery');
      await bMessages.cancel();
      await cMessages.cancel();
      await transport.dispose();
    },
  );
}
