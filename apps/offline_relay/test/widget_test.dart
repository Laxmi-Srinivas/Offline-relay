import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/main.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:offline_relay/ui/screens/chat_screen.dart';
import 'package:relay_transport/relay_transport.dart';

void main() {
  testWidgets(
    'existing shell survives narrow portrait, landscape and keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(OfflineRelayApp(transport: _WidgetTransport()));
      for (final size in [const Size(320, 640), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final tab in ['Profile', 'Nearby', 'Home']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Avery Long Name');
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Avery Long Name'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('chat terminal and automatic encryption setup scroll in landscape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _chatController();
    controller.securityState = RelaySecurityState.exchangingKeys;
    controller.remoteName =
        'A very long helper name that should wrap without overflow';
    Widget screen() => MaterialApp(
      home: ChatScreen(
        controller: controller,
        onEndChat: () async {},
        onReturnToNearby: () async {},
        onSubmitReport: (_, _) async {},
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(tester.takeException(), isNull);
    controller.chatEndReason = RelayChatEndReason.connectionLost;
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('Home screen and bottom navigation render the new shell', (
    tester,
  ) async {
    await tester.pumpWidget(const OfflineRelayApp());
    await tester.pump();

    expect(find.text('OfflineRelay'), findsOneWidget);
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

  testWidgets('chat places End in the top app bar and confirms before ending', (
    tester,
  ) async {
    final controller = _chatController();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          controller: controller,
          onEndChat: () async {},
          onReturnToNearby: () async {},
          onSubmitReport: (_, _) async {},
        ),
      ),
    );

    final endButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('End'),
    );
    expect(endButton, findsOneWidget);
    await tester.tap(endButton);
    await tester.pumpAndSettle();
    expect(find.text('End this chat?'), findsOneWidget);
    expect(find.text('Keep chatting'), findsOneWidget);
    await tester.tap(find.text('Keep chatting'));
    await tester.pumpAndSettle();
    expect(controller.inChat, isTrue);
    controller.dispose();
  });

  testWidgets('report is a local chat action with an honest confirmation', (
    tester,
  ) async {
    final controller = _chatController();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          controller: controller,
          onEndChat: () async {},
          onReturnToNearby: () async {},
          onSubmitReport: (reason, note) async =>
              controller.submitLocalReport(reason: reason, note: note),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Report this person'));
    await tester.pumpAndSettle();
    expect(find.text('What happened?'), findsOneWidget);
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(find.text('Report noted'), findsOneWidget);
    expect(
      find.textContaining('not sent to a moderation service'),
      findsOneWidget,
    );
    expect(controller.hasSubmittedReport, isTrue);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    controller.dispose();
  });
}

RelayDemoController _chatController() {
  final controller = RelayDemoController(_WidgetTransport());
  controller
    ..inChat = true
    ..remoteName = 'Avery'
    ..remoteRoleLabel = 'Internet Helper'
    ..securityState = RelaySecurityState.ready;
  return controller;
}

class _WidgetTransport implements RelayTransport {
  final _incoming = StreamController<RelayConnection>.broadcast();

  @override
  Stream<RelayConnection> get incomingConnections => _incoming.stream;

  @override
  Future<RelayConnection> connect(RelayPeer peer) => throw UnimplementedError();

  @override
  Stream<RelayPeer> discover() => const Stream<RelayPeer>.empty();

  @override
  Future<void> advertise(RelayProfile profile) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> dispose() => _incoming.close();
}
