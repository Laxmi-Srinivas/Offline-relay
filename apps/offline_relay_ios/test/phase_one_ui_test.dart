import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/main.dart';
import 'package:offline_relay/transport/helper_availability.dart';
import 'package:relay_transport/relay_transport.dart';

class UiLink implements RelayConnection {
  UiLink(this.peer);
  @override
  final RelayPeer peer;
  final events = StreamController<Uint8List>.broadcast();
  final sent = <RelayEnvelope>[];
  bool closed = false;
  @override
  int get maxMessageBytes => relayMaxMessageBytes;
  @override
  Stream<Uint8List> get messages => events.stream;
  @override
  Future<void> send(Uint8List bytes) async {
    sent.add(RelayEnvelope.decode(bytes));
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  void accept() => emit(
    RelayEnvelope.create(
      type: RelayMessageType.connectionAccept,
      body: {'requestId': sent.first.id},
    ),
  );
  void reject() => emit(
    RelayEnvelope.create(
      type: RelayMessageType.connectionReject,
      body: {'requestId': sent.first.id},
    ),
  );
  void emit(RelayEnvelope envelope) => events.add(envelope.encode());
}

class UiTransport implements RelayTransport, HelperAvailabilityControl {
  final incoming = StreamController<RelayConnection>.broadcast();
  final discoveries = StreamController<RelayPeer>.broadcast();
  final availability = StreamController<HelperAvailabilityState>.broadcast();
  final accepted = StreamController<HelperAcceptedEvent>.broadcast();
  final links = <String, UiLink>{};
  bool offered = false;
  bool stopped = false;
  @override
  Stream<RelayConnection> get incomingConnections => incoming.stream;
  @override
  Stream<HelperAvailabilityState> get availabilityStates => availability.stream;
  @override
  Stream<HelperAcceptedEvent> get acceptedConnections => accepted.stream;
  @override
  Stream<RelayPeer> discover() => discoveries.stream;
  @override
  Future<RelayConnection> connect(RelayPeer peer) async =>
      links.putIfAbsent(peer.id, () => UiLink(peer));
  @override
  Future<void> advertise(RelayProfile profile) async {
    offered = true;
  }

  @override
  Future<void> stopAdvertising() async {}
  @override
  Future<void> stopHelperAvailability() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    await incoming.close();
    await discoveries.close();
    await availability.close();
    await accepted.close();
    for (final link in links.values) {
      await link.events.close();
    }
  }
}

final helperB = RelayPeer(
  id: 'B',
  label: 'Helper B',
  metadata: {'role': 'internet_helper'},
);
final helperC = RelayPeer(
  id: 'C',
  label: 'Helper C',
  metadata: {'role': 'internet_helper'},
);

void main() {
  late UiTransport transport;
  Future<void> start(WidgetTester tester) async {
    transport = UiTransport();
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OfflineRelayApp(transport: transport));
    await tester.pump();
  }

  Future<void> name(WidgetTester tester) async {
    await tester.tap(find.text('Profile').last);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Avery');
    await tester.pump();
  }

  Future<void> search(WidgetTester tester) async {
    await name(tester);
    await tester.tap(find.text('Home').last);
    await tester.pump();
    await tester.ensureVisible(find.text('Find People Nearby').first);
    await tester.tap(find.text('Find People Nearby').first);
    await tester.pump();
    transport.discoveries.add(helperB);
    transport.discoveries.add(helperC);
    await tester.pump();
  }

  Future<void> connect(WidgetTester tester, String label) async {
    final card = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    final button = find.descendant(
      of: card,
      matching: find.widgetWithText(FilledButton, 'Connect'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets('Find Nearby without name routes to Profile', (tester) async {
    await start(tester);
    await tester.tap(find.text('Find People Nearby').first);
    await tester.pump();
    expect(find.text('Your profile'), findsOneWidget);
    expect(
      find.text('Add your name in Profile to get started.'),
      findsOneWidget,
    );
    expect(transport.links, isEmpty);
  });
  testWidgets(
    'two helper cards remain actionable; first acceptance enters only winner chat',
    (tester) async {
      await start(tester);
      await search(tester);
      expect(find.text('People nearby'), findsOneWidget);
      await connect(tester, 'Helper B');
      expect(find.text('Requesting…'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      await connect(tester, 'Helper C');
      expect(find.text('Requesting…'), findsNWidgets(2));
      expect(transport.links['B']!.closed, isFalse);
      // Switching tabs and using Find Nearby must not restart/cancel requests.
      await tester.tap(find.text('Home').last);
      await tester.pump();
      await tester.ensureVisible(find.text('Find People Nearby').first);
      await tester.tap(find.text('Find People Nearby').first);
      await tester.pump();
      expect(find.text('Requesting…'), findsNWidgets(2));
      transport.links['C']!.accept();
      transport.links['B']!.accept();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('Chat with Helper C'), findsOneWidget);
      expect(transport.links['B']!.closed, isTrue);
      transport.links['B']!.emit(
        RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'loser injection'},
        ),
      );
      transport.links['C']!.emit(
        RelayEnvelope.create(
          type: RelayMessageType.chat,
          body: {'text': 'winner message'},
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('loser injection'), findsNothing);
      expect(find.text('winner message'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hello C');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(transport.links['C']!.sent.last.body['text'], 'Hello C');
      await tester.tap(find.byTooltip('End chat and return to Nearby'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('People nearby'), findsOneWidget);
      expect(transport.links['C']!.closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('one declined request leaves the other card pending', (
    tester,
  ) async {
    await start(tester);
    await search(tester);
    await connect(tester, 'Helper B');
    await connect(tester, 'Helper C');
    transport.links['B']!.reject();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Requesting…'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(transport.links['C']!.closed, isFalse);
    expect(transport.links['B']!.closed, isTrue);
    transport.links['C']!.accept();
    await tester.pump();
    expect(find.text('Chat with Helper C'), findsOneWidget);
  });
  testWidgets(
    'Profile helper toggle and incoming request navigate to Nearby and chat',
    (tester) async {
      await start(tester);
      await name(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(transport.offered, isTrue);
      await tester.tap(find.text('Home').last);
      await tester.pump();
      final incoming = UiLink(RelayPeer(id: 'offline', label: 'Offline peer'));
      transport.links['offline'] = incoming;
      transport.incoming.add(incoming);
      await tester.pump();
      incoming.emit(
        RelayEnvelope.create(
          type: RelayMessageType.connectionRequest,
          body: {'name': 'Morgan', 'role': 'offline_user'},
        ),
      );
      await tester.pump();
      expect(find.text('People nearby'), findsOneWidget);
      expect(find.text('Morgan wants to connect'), findsOneWidget);
      await tester.ensureVisible(find.text('Accept'));
      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Chat with Morgan'), findsOneWidget);
      expect(incoming.sent.last.type, RelayMessageType.connectionAccept);
    },
  );
  testWidgets('Profile can disable Help Others and replay restored name', (
    tester,
  ) async {
    await start(tester);
    await name(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump();
    expect(transport.offered, isTrue);
    transport.availability.add(
      const HelperAvailabilityState(enabled: true, displayName: 'Restored'),
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Restored',
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump();
    expect(transport.stopped, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
  testWidgets('empty search displays Phase 1 no-people state', (tester) async {
    await start(tester);
    await name(tester);
    await tester.tap(find.text('Nearby').last);
    await tester.pump();
    await tester.tap(find.text('Find People Nearby'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 13));
    expect(find.text('No one found nearby'), findsOneWidget);
    expect(find.text('Search Again'), findsOneWidget);
  });
}
