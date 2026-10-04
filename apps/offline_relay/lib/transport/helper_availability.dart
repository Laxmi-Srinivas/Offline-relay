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
  });

  final String connectionId;
  final String? requestId;
  final String peerName;
}
