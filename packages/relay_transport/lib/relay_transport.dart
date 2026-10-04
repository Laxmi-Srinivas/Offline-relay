/// Transport boundary only. No networking implementation is provided here.
library;

import 'dart:typed_data';

/// An opaque identifier scoped to one transport's discovery session.
final class RelayPeer {
  const RelayPeer({required this.id, required this.label});

  final String id;
  final String label;
}

/// Implementations translate native failures into stream errors or exceptions.
/// Discovery runs until cancellation; cancellation must stop native discovery.
abstract interface class RelayTransport {
  Stream<RelayPeer> discover();

  Future<RelayConnection> connect(RelayPeer peer);

  /// Stop discovery and release all owned connections and native resources.
  Future<void> dispose();
}

/// A connection transports complete, bounded messages, not raw stream chunks.
/// Adapters own fragmentation/reassembly and enforce [maxMessageBytes].
/// Receive streams end on disconnect and report failures as stream errors.
abstract interface class RelayConnection {
  RelayPeer get peer;
  int get maxMessageBytes;
  Stream<Uint8List> get messages;

  /// Completion means transport acceptance, not application acknowledgement.
  /// Reject oversize messages and sends after close. Do not silently truncate.
  Future<void> send(Uint8List message);

  /// Idempotently close the connection and release native resources.
  Future<void> close();
}
