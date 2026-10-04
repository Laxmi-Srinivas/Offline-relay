/// Transport boundary only. No networking implementation is provided here.
library;

import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

const int relayMaxMessageBytes = 256;

/// Profile information published by a local user while advertising.
/// Metadata is intentionally small and application-defined.
final class RelayProfile {
  RelayProfile({
    required this.id,
    required this.label,
    Map<String, String> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    if (id.isEmpty || label.isEmpty) {
      throw ArgumentError('Profile id and label must not be empty');
    }
  }

  final String id;
  final String label;
  final Map<String, String> metadata;
}

/// An opaque identifier scoped to one transport's discovery session.
final class RelayPeer {
  RelayPeer({
    required this.id,
    required this.label,
    Map<String, String> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata);

  final String id;
  final String label;
  final Map<String, String> metadata;
}

/// Implementations translate native failures into stream errors or exceptions.
/// Discovery runs until cancellation; cancellation must stop native discovery.
abstract interface class RelayTransport {
  Stream<RelayPeer> discover();

  Future<RelayConnection> connect(RelayPeer peer);

  /// Advertise this profile until [stopAdvertising] or [dispose].
  Future<void> advertise(RelayProfile profile);

  /// Incoming BLE links are surfaced before app-level acceptance. The app
  /// must exchange a `connection_accept` envelope before enabling chat.
  Stream<RelayConnection> get incomingConnections;

  Future<void> stopAdvertising();

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

enum RelayMessageType {
  connectionRequest('connection_request'),
  connectionAccept('connection_accept'),
  connectionReject('connection_reject'),
  chat('chat'),
  serviceRequest('service_request'),
  serviceResponse('service_response');

  const RelayMessageType(this.wireName);

  final String wireName;

  static RelayMessageType parse(String value) =>
      RelayMessageType.values.firstWhere(
        (type) => type.wireName == value,
        orElse: () => throw FormatException('Unknown message type: $value'),
      );
}

/// Version 1 application envelope. The complete UTF-8 JSON representation,
/// including its envelope fields, must fit in the transport's 256-byte limit.
final class RelayEnvelope {
  RelayEnvelope({
    required this.id,
    required this.type,
    required Map<String, Object?> body,
    this.version = 1,
  }) : body = Map.unmodifiable(body) {
    if (version != 1) throw ArgumentError.value(version, 'version');
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
  }

  static final Random _random = Random.secure();

  final int version;
  final String id;
  final RelayMessageType type;
  final Map<String, Object?> body;

  factory RelayEnvelope.create({
    required RelayMessageType type,
    required Map<String, Object?> body,
  }) => RelayEnvelope(id: _newId(), type: type, body: body);

  static String _newId() => List<int>.generate(
    16,
    (_) => _random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  Uint8List encode({int maxBytes = relayMaxMessageBytes}) {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': version,
          'id': id,
          'type': type.wireName,
          'body': body,
        }),
      ),
    );
    if (bytes.length > maxBytes) {
      throw FormatException(
        'Encoded envelope is ${bytes.length} bytes; maximum is $maxBytes',
      );
    }
    return bytes;
  }

  factory RelayEnvelope.decode(
    List<int> bytes, {
    int maxBytes = relayMaxMessageBytes,
  }) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw FormatException('Envelope must be 1..$maxBytes bytes');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid UTF-8 envelope: $error');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 4 ||
        !decoded.keys.toSet().containsAll({'version', 'id', 'type', 'body'})) {
      throw const FormatException(
        'Envelope must contain version, id, type, body',
      );
    }
    final version = decoded['version'];
    final id = decoded['id'];
    final type = decoded['type'];
    final body = decoded['body'];
    if (version != 1 ||
        id is! String ||
        id.isEmpty ||
        type is! String ||
        body is! Map<String, dynamic>) {
      throw const FormatException('Malformed version 1 envelope');
    }
    return RelayEnvelope(
      version: version,
      id: id,
      type: RelayMessageType.parse(type),
      body: Map<String, Object?>.from(body),
    );
  }
}
