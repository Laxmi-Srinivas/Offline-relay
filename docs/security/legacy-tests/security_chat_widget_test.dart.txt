import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/main.dart';
import 'package:relay_transport/relay_transport.dart';

void main() {
  testWidgets('disconnect clears the editor draft before a different chat', (
    tester,
  ) async {
    const methods = MethodChannel('dev.offlinerelay/ble/methods');
    const events = MethodChannel('dev.offlinerelay/ble/events');
    const codec = StandardMethodCodec();
    final messenger = tester.binding.defaultBinaryMessenger;
    RelayEnvelope? request;
    var nextId = 0;
    var connectionId = '';
    final peer = {
      'id': 'test-peer',
      'label': 'Test helper',
      'metadata': {'role': 'internet_helper'},
    };
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'connect') {
        connectionId = 'test-session-${++nextId}';
        return {'connectionId': connectionId, 'peer': peer};
      }
      if (call.method == 'send') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        request = RelayEnvelope.decode(args['message'] as Uint8List);
      }
      return null;
    });

    void emit(Map<String, Object?> event) {
      tester.binding.channelBuffers.push(
        events.name,
        codec.encodeSuccessEnvelope(event),
        (_) {},
      );
    }

    Future<void> connectAndAccept() async {
      await tester.tap(find.text('Find Nearby Helpers'));
      await tester.pumpAndSettle();
      emit({'event': 'peerDiscovered', 'peer': peer});
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      // The waiting-for-approval progress indicator intentionally animates.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(request!.type, RelayMessageType.connectionRequest);
      emit({
        'event': 'message',
        'connectionId': connectionId,
        'message': RelayEnvelope.create(
          type: RelayMessageType.connectionAccept,
          body: {'requestId': request!.id},
        ).encode(),
      });
      await tester.pumpAndSettle();
      expect(find.text('Chat with Test helper'), findsOneWidget);
    }

    await tester.pumpWidget(const OfflineRelayApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test user');
    await connectAndAccept();
    await tester.enterText(find.byType(TextField), 'synthetic private draft');
    emit({
      'event': 'disconnected',
      'connectionId': connectionId,
      'reason': 'test disconnect',
    });
    await tester.pumpAndSettle();
    expect(find.text('Nearby Users'), findsOneWidget);
    await connectAndAccept();
    final editor = tester.widget<TextField>(find.byType(TextField));
    expect(editor.controller!.text, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });
}
