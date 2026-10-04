import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/relay_demo_controller.dart';
import 'package:offline_relay/transport/helper_availability.dart';
import 'package:relay_transport/relay_transport.dart';

import 'security_controller_test.dart'
    show TestTransport, TestConnection, flush;

class HelperTransport extends TestTransport
    implements HelperAvailabilityControl {
  final states = StreamController<HelperAvailabilityState>.broadcast();
  final approvals = StreamController<HelperAcceptedEvent>.broadcast();
  @override
  Stream<HelperAvailabilityState> get availabilityStates => states.stream;
  @override
  Stream<HelperAcceptedEvent> get acceptedConnections => approvals.stream;
  @override
  Future<void> stopHelperAvailability() async {}
  @override
  Future<void> dispose() async {
    await super.dispose();
    await states.close();
    await approvals.close();
  }
}

void main() {
  late HelperTransport transport;
  late RelayDemoController controller;
  late TestConnection connection;
  setUp(() async {
    transport = HelperTransport();
    controller = RelayDemoController(transport);
    controller.updateProfile(
      name: 'Helper',
      role: RelayUserRole.internetHelper,
    );
    await controller.offerHelp();
    connection = TestConnection('B');
    transport.incoming.add(connection);
    await flush();
    connection.emit(RelayMessageType.connectionRequest, {
      'name': 'B',
      'role': 'offline_user',
    }, id: 'request-B');
    await flush();
  });
  tearDown(() async {
    controller.dispose();
    await flush();
  });
  void approve(TestConnection peer, String? requestId) {
    transport.approvals.add(
      HelperAcceptedEvent(
        connectionId: peer.peer.id,
        requestId: requestId,
        peerName: peer.peer.label,
        connection: peer,
      ),
    );
  }

  test(
    'invalid request metadata cannot create or replace the approval prompt',
    () async {
      await controller.returnToNearby();
      await controller.offerHelp();
      final peer = TestConnection('metadata');
      transport.incoming.add(peer);
      await flush();
      for (final body in <Map<String, Object?>>[
        {'name': 123, 'role': 'offline_user'},
        {'name': '', 'role': 'offline_user'},
        {'name': 'Other role', 'role': 'internet_helper'},
      ]) {
        peer.emit(RelayMessageType.connectionRequest, body);
      }
      await flush();
      expect(controller.hasIncomingRequest, false);
      peer.emit(RelayMessageType.connectionRequest, {
        'name': 'First',
        'role': 'offline_user',
      }, id: 'first');
      peer.emit(RelayMessageType.connectionRequest, {
        'name': 'Replacement',
        'role': 'offline_user',
      }, id: 'replacement');
      await flush();
      expect(controller.incomingRequestId, 'first');
      expect(controller.incomingPeerName, 'First');
    },
  );
  test('old connection approval cannot approve replacement peer', () async {
    approve(TestConnection('A'), 'request-A');
    await flush();
    expect(controller.inChat, isFalse);
    expect(controller.incomingRequestId, 'request-B');
    connection.emit(RelayMessageType.chat, {'text': 'unapproved'});
    await flush();
    expect(controller.messages, isEmpty);
  });
  test(
    'wrong or absent request approval cannot approve current peer',
    () async {
      approve(connection, 'request-A');
      approve(connection, null);
      await flush();
      expect(controller.inChat, isFalse);
      expect(controller.incomingRequestId, 'request-B');
    },
  );
  test(
    'matching restored approval closes the connection when its keys are lost',
    () async {
      approve(connection, 'request-B');
      await flush();
      expect(controller.inChat, isFalse);
      expect(connection.closed, isTrue);
      expect(controller.chatEndReason, RelayChatEndReason.connectionLost);
      connection.emit(RelayMessageType.chat, {'text': 'approved'});
      await flush();
      expect(controller.messages, isEmpty);
    },
  );
  test('late approval after leaving cannot revive a conversation', () async {
    await controller.returnToNearby();
    approve(connection, 'request-B');
    await flush();
    expect(controller.inChat, isFalse);
    expect(controller.remoteName, isNull);
  });
}
