import 'package:ble_poc/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Channel harness tests only. They provide no Bluetooth/networking evidence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const commands = MethodChannel('offlinerelay.poc/commands');
  const events = MethodChannel('offlinerelay.poc/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  testWidgets(
    'role selection invokes native command without claiming success',
    (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(commands, (call) async {
        calls.add(call.method);
        return null;
      });
      await tester.pumpWidget(const MaterialApp(home: BleDiagnostics()));
      await tester.tap(find.text('A: Discover + connect'));
      await tester.pump();
      expect(calls, ['discover']);
      expect(find.textContaining('connection_established'), findsNothing);
      expect(find.textContaining('acknowledgement_received'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('native errors are surfaced in diagnostics', (tester) async {
    messenger.setMockMethodCallHandler(commands, (_) async {
      throw PlatformException(code: 'ble_error', message: 'Bluetooth disabled');
    });
    await tester.pumpWidget(const MaterialApp(home: BleDiagnostics()));
    await tester.tap(find.text('B: Advertise'));
    await tester.pumpAndSettle();
    expect(find.text('ble_error: Bluetooth disabled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('iOS role controls route peripheral, central, and stop', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(commands, (call) async {
      calls.add(call.method);
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: BleDiagnostics()));
    await tester.tap(find.text('PERIPHERAL: Advertise'));
    await tester.pump();
    await tester.tap(find.text('CENTRAL: Discover + connect'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(calls, ['advertise', 'discover', 'stop']);
    expect(find.textContaining('advertising_started'), findsNothing);
    expect(find.textContaining('acknowledgement_received'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
