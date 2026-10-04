import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:offline_relay/ui/screens/chat_screen.dart';

import 'security_controller_test.dart' show TestTransport;

void main() {
  testWidgets(
    'ending a conversation clears its editor before a replacement chat',
    (tester) async {
      final controller = RelayDemoController(TestTransport());
      controller.inChat = true;
      controller.securityState = RelaySecurityState.ready;
      controller.remoteName = 'A';
      Widget screen() => MaterialApp(
        home: ChatScreen(
          controller: controller,
          onEndChat: () async {},
          onReturnToNearby: () async {},
          onSubmitReport: (_, _) async {},
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'synthetic private draft');
      controller.inChat = false;
      controller.chatEndReason = RelayChatEndReason.connectionLost;
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      controller.inChat = true;
      controller.chatEndReason = null;
      controller.remoteName = 'B';
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final editor = tester.widget<TextField>(find.byType(TextField));
      expect(editor.controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
