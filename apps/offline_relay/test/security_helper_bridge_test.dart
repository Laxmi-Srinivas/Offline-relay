import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:offline_relay/transport/ble_relay_transport.dart';
import 'package:relay_transport/relay_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('dev.offlinerelay/ble/methods');
  const events = MethodChannel('dev.offlinerelay/ble/events');
  const codec = StandardMethodCodec();
  late RelayDemoController controller;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    messenger.setMockMethodCallHandler(methods, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    controller = RelayDemoController(BleRelayTransport());
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });
  void emit(Map<String, Object?> event) {
    TestWidgetsFlutterBinding.instance.channelBuffers.push(
      events.name,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  void snapshot(String? id, {bool accepted = false}) {
    emit({'event': 'helperState', 'enabled': true, 'displayName': 'Helper'});
    emit({'event': 'helperSnapshot', 'connectionId': id});
    if (id == null) return;
    emit({
      'event': 'incomingConnection',
      'connectionId': id,
      'peer': {
        'id': id,
        'label': id,
        'metadata': {'role': 'offline_user'},
      },
    });
    emit({
      'event': 'message',
      'connectionId': id,
      'message': RelayEnvelope(
        id: 'request-$id',
        type: RelayMessageType.connectionRequest,
        body: {'name': id, 'role': 'offline_user'},
      ).encode(),
    });
    if (accepted) {
      emit({
        'event': 'helperAccepted',
        'connectionId': id,
        'requestId': 'request-$id',
        'peerName': id,
      });
    }
  }

  test(
    'native snapshot restores approval before queued chat delivery',
    () async {
      snapshot('A', accepted: true);
      emit({
        'event': 'message',
        'connectionId': 'A',
        'message': RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'background test'},
        ).encode(),
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.inChat, isTrue);
      expect(controller.messages.single.text, 'background test');
    },
  );
  test(
    'replacement snapshot ends old chat before exposing new request',
    () async {
      snapshot('A', accepted: true);
      await Future<void>.delayed(Duration.zero);
      snapshot('B');
      emit({
        'event': 'helperAccepted',
        'connectionId': 'A',
        'requestId': 'request-A',
        'peerName': 'A',
      });
      emit({
        'event': 'message',
        'connectionId': 'A',
        'message': RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'old'},
        ).encode(),
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.inChat, isFalse);
      expect(controller.incomingRequestId, 'request-B');
      expect(controller.messages, isEmpty);
    },
  );
  test(
    'empty snapshot clears a conversation ended while UI detached',
    () async {
      snapshot('A', accepted: true);
      await Future<void>.delayed(Duration.zero);
      snapshot(null);
      await Future<void>.delayed(Duration.zero);
      expect(controller.inChat, isFalse);
      expect(controller.remoteName, isNull);
    },
  );
  test('same live snapshot preserves existing approved chat', () async {
    snapshot('A', accepted: true);
    await Future<void>.delayed(Duration.zero);
    await controller.sendChat('synthetic local');
    snapshot('A', accepted: true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.inChat, isTrue);
    expect(controller.messages.single.text, 'synthetic local');
  });
}
