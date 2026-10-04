import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/main.dart';

void main() {
  testWidgets('Home screen and bottom navigation render the new shell', (
    tester,
  ) async {
    await tester.pumpWidget(const OfflineRelayApp());
    await tester.pump();

    expect(find.text('onya'), findsOneWidget);
    expect(find.text('No internet?\nGet help nearby.'), findsOneWidget);
    expect(find.text('Find People Nearby'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Nearby').last);
    await tester.pumpAndSettle();
    expect(find.text('People nearby'), findsOneWidget);
    expect(
      find.text('Search for people nearby who have chosen to offer help.'),
      findsOneWidget,
    );
    expect(find.text('Find People Nearby'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Profile exposes a name field and real helper availability state',
    (tester) async {
      await tester.pumpWidget(const OfflineRelayApp());
      await tester.pump();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Your profile'), findsOneWidget);
      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Available to help nearby'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
