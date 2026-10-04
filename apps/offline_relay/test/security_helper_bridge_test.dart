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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RelayDemoController controller;
  setUp(() async {
    messenger.setMockMethodCallHandler(methods, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    controller = RelayDemoController(BleRelayTransport());
    controller.updateProfile(
      name: 'Helper',
      role: RelayUserRole.internetHelper,
    );
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

  Future<void> request(String id) async {
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
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'replacement native snapshot retires an ended detached request',
    () async {
      await request('A');
      emit({'event': 'helperSnapshot', 'connectionId': 'B'});
      await request('B');
      expect(controller.incomingRequestId, 'request-B');
      expect(controller.incomingPeerName, 'B');
      expect(controller.messages, isEmpty);
    },
  );
  test('accepted snapshot without a pending request closes the lost-key connection', () async {
    emit({
      'event': 'incomingConnection',
      'connectionId': 'B',
      'peer': {
        'id': 'B',
        'label': 'B',
        'metadata': {'role': 'offline_user'},
      },
    });
    emit({
      'event': 'helperAccepted',
      'connectionId': 'B',
      'requestId': 'request-B',
      'peerName': 'B',
    });
    await Future<void>.delayed(Duration.zero);
    expect(controller.chatEndReason, RelayChatEndReason.connectionLost);
    expect(controller.inChat, false);
  });
  test(
    'unknown native approval cannot close the replacement request',
    () async {
      await request('B');
      emit({
        'event': 'helperAccepted',
        'connectionId': 'A',
        'requestId': 'request-A',
        'peerName': 'A',
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.incomingRequestId, 'request-B');
      expect(controller.isChatTerminal, false);
    },
  );
  test('wrong request approval for live connection is ignored', () async {
    await request('B');
    emit({
      'event': 'helperAccepted',
      'connectionId': 'B',
      'requestId': 'request-A',
      'peerName': 'A',
    });
    await Future<void>.delayed(Duration.zero);
    expect(controller.incomingRequestId, 'request-B');
    expect(controller.isChatTerminal, false);
  });
  test(
    'matching restored approval fails closed instead of reusing lost keys',
    () async {
      await request('B');
      emit({
        'event': 'helperAccepted',
        'connectionId': 'B',
        'requestId': 'request-B',
        'peerName': 'B',
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.inChat, false);
      expect(controller.chatEndReason, RelayChatEndReason.connectionLost);
    },
  );
  test(
    'disconnect followed by a new request keeps sessions separate',
    () async {
      await request('A');
      emit({'event': 'disconnected', 'connectionId': 'A'});
      await Future<void>.delayed(Duration.zero);
      await request('B');
      emit({
        'event': 'message',
        'connectionId': 'A',
        'message': RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'old'},
        ).encode(),
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.incomingRequestId, 'request-B');
      expect(controller.messages, isEmpty);
    },
  );
}
