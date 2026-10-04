import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/main.dart';

void main() {
  testWidgets('foundation starts without networking', (tester) async {
    await tester.pumpWidget(const OfflineRelayFoundation());
    expect(find.text('OfflineRelay — engineering foundation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
