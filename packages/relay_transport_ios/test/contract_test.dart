import 'dart:convert';

import '../lib/relay_transport.dart';

// Dependency-free checks of the pure Dart package contract.
void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void main() {
  for (final type in RelayMessageType.values) {
    final value = RelayEnvelope.create(type: type, body: {'text': 'Hello 🌍'});
    final decoded = RelayEnvelope.decode(value.encode());
    check(decoded.type == type && decoded.id == value.id, 'envelope identity');
    check(decoded.body['text'] == 'Hello 🌍', 'UTF-8 body');
  }
  final profile = RelayProfile(
    id: 'local',
    label: 'Helper',
    metadata: {'role': 'internet_helper'},
  );
  check(profile.metadata['role'] == 'internet_helper', 'profile role');
  var rejected = false;
  try {
    RelayEnvelope.decode(utf8.encode('{"version":2}'));
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'reject malformed envelope');
  final empty = RelayEnvelope(
    id: 'x',
    type: RelayMessageType.chat,
    body: {'text': ''},
  );
  final count = relayMaxMessageBytes - empty.encode().length;
  final exact = RelayEnvelope(
    id: 'x',
    type: RelayMessageType.chat,
    body: {'text': 'a' * count},
  );
  check(exact.encode().length == 256, '256-byte boundary');
  rejected = false;
  try {
    RelayEnvelope(
      id: 'x',
      type: RelayMessageType.chat,
      body: {'text': 'a' * (count + 1)},
    ).encode();
  } on FormatException {
    rejected = true;
  }
  check(rejected, '257-byte rejection');
  print(
    'PASS: relay_transport envelopes, UTF-8, profiles, malformed data, byte limits',
  );
}
