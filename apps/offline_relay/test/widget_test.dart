import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/main.dart';

void main() {
  testWidgets('Nearby Users screen starts with role choices', (tester) async {
    await tester.pumpWidget(const OfflineRelayApp());
    await tester.pump();

    expect(find.text('Nearby Users'), findsOneWidget);
    expect(find.text('Find Nearby Helpers'), findsOneWidget);
    expect(find.text('Your display name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
