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
  final calls = <MethodCall>[];
  const peer = {
    'id': 'offline-peer',
    'label': 'Nearby user',
    'metadata': <String, String>{},
  };

  Future<void> emit(Map<String, Object> event) async {
    // ignore: deprecated_member_use
    await messenger.handlePlatformMessage(
      events.name,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> incomingRequest({String id = 'helper-link'}) async {
    await emit({
      'event': 'incomingConnection',
      'connectionId': id,
      'peer': peer,
    });
    await emit({
      'event': 'message',
      'connectionId': id,
      'message': RelayEnvelope(
        id: 'request-1',
        type: RelayMessageType.connectionRequest,
        body: {'name': 'Avery', 'role': 'offline_user'},
      ).encode(),
    });
  }

  Future<void> dispose(RelayDemoController controller) async {
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(methods, null);
  });

  test(
    'enable and explicitly disable helper availability through channel',
    () async {
      final controller = RelayDemoController(BleRelayTransport());
      controller.updateProfile(
        name: 'Helper',
        role: RelayUserRole.internetHelper,
      );
      await controller.offerHelp();
      expect(controller.isOffering, isTrue);
      expect(calls.last.method, 'advertise');
      expect((calls.last.arguments as Map)['profile']['metadata'], {
        'role': 'internet_helper',
      });
      await controller.stopOfferingHelp();
      expect(calls.last.method, 'stopHelper');
      expect(controller.isOffering, isFalse);
      expect(controller.status, 'Help Others is off.');
      await dispose(controller);
    },
  );

  test(
    'helperState reconstructs name role and availability into controller',
    () async {
      final controller = RelayDemoController(BleRelayTransport());
      await emit({
        'event': 'helperState',
        'enabled': true,
        'displayName': 'Restored Helper',
      });
      expect(controller.role, RelayUserRole.internetHelper);
      expect(controller.displayName, 'Restored Helper');
      expect(controller.isOffering, isTrue);
      await emit({
        'event': 'helperState',
        'enabled': false,
        'displayName': 'Restored Helper',
      });
      expect(controller.isOffering, isFalse);
      expect(controller.status, 'Help Others is off.');
      await dispose(controller);
    },
  );

  test(
    'Reject sends reject and closes link without disabling availability',
    () async {
      final controller = RelayDemoController(BleRelayTransport());
      await emit({
        'event': 'helperState',
        'enabled': true,
        'displayName': 'Helper',
      });
      await incomingRequest();
      expect(controller.hasIncomingRequest, isTrue);
      await controller.rejectIncomingRequest();
      final sent = calls.singleWhere((call) => call.method == 'send');
      final envelope = RelayEnvelope.decode(
        (sent.arguments as Map)['message'] as Uint8List,
      );
      expect(envelope.type, RelayMessageType.connectionReject);
      expect(envelope.body['requestId'], 'request-1');
      expect(calls.any((call) => call.method == 'close'), isTrue);
      expect(calls.any((call) => call.method == 'stopHelper'), isFalse);
      expect(controller.isOffering, isTrue);
      expect(controller.hasIncomingRequest, isFalse);
      await dispose(controller);
    },
  );

  test(
    'helperAccepted replay restores connection and bidirectional chat',
    () async {
      final controller = RelayDemoController(BleRelayTransport());
      await emit({
        'event': 'helperState',
        'enabled': true,
        'displayName': 'Helper',
      });
      await incomingRequest();
      await emit({
        'event': 'helperAccepted',
        'connectionId': 'helper-link',
        'requestId': 'request-1',
        'peerName': 'Avery',
      });
      expect(controller.inChat, isTrue);
      expect(controller.hasIncomingRequest, isFalse);
      expect(controller.remoteName, 'Avery');
      await controller.sendChat('Hello after reattach');
      final sent = calls.last.arguments as Map;
      expect(sent['connectionId'], 'helper-link');
      expect(
        RelayEnvelope.decode(sent['message'] as Uint8List).body['text'],
        'Hello after reattach',
      );
      await emit({
        'event': 'message',
        'connectionId': 'helper-link',
        'message': RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'Reply'},
        ).encode(),
      });
      expect(controller.messages.map((message) => message.text), [
        'Hello after reattach',
        'Reply',
      ]);
      await controller.returnToNearby();
      expect(controller.inChat, isFalse);
      expect(
        calls.map((call) => call.method),
        containsAllInOrder(['close', 'stopAdvertising', 'stopHelper']),
      );
      await dispose(controller);
    },
  );

  test(
    'duplicate incoming replay does not replace an accepted chat link',
    () async {
      final controller = RelayDemoController(BleRelayTransport());
      await emit({
        'event': 'helperState',
        'enabled': true,
        'displayName': 'Helper',
      });
      await incomingRequest();
      await controller.acceptIncomingRequest();
      expect(controller.inChat, isTrue);
      await emit({
        'event': 'incomingConnection',
        'connectionId': 'helper-link',
        'peer': peer,
      });
      expect(controller.inChat, isTrue);
      expect(calls.where((call) => call.method == 'close'), isEmpty);
      await dispose(controller);
    },
  );
  test(
    'disconnect releases accepted link so availability can accept another',
    () async {
      final controller = RelayDemoController(BleRelayTransport());
      await emit({
        'event': 'helperState',
        'enabled': true,
        'displayName': 'Helper',
      });
      await incomingRequest();
      await controller.acceptIncomingRequest();
      await emit({
        'event': 'disconnected',
        'connectionId': 'helper-link',
        'reason': 'Peer left',
      });
      expect(controller.inChat, isFalse);
      await emit({
        'event': 'helperState',
        'enabled': true,
        'displayName': 'Helper',
      });
      await incomingRequest(id: 'replacement-link');
      expect(controller.hasIncomingRequest, isTrue);
      await controller.acceptIncomingRequest();
      expect(controller.inChat, isTrue);
      await dispose(controller);
    },
  );
}
