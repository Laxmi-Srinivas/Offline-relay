import 'package:relay_transport/relay_transport.dart';

/// App-level controls exposed by the Android helper foreground service.
abstract interface class HelperAvailabilityControl {
  Stream<HelperAvailabilityState> get availabilityStates;

  Stream<HelperAcceptedEvent> get acceptedConnections;

  Future<void> stopHelperAvailability();
}

class HelperAvailabilityState {
  const HelperAvailabilityState({required this.enabled, this.displayName});

  final bool enabled;
  final String? displayName;
}

class HelperAcceptedEvent {
  const HelperAcceptedEvent({
    required this.connectionId,
    required this.requestId,
    required this.peerName,
    this.connection,
  });

  final String connectionId;
  final String? requestId;
  final String peerName;
  final RelayConnection? connection;
}
