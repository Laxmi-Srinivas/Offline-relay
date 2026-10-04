import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_transport/relay_transport.dart';

void main() {
  test('encodes and decodes every supported message type as UTF-8 JSON', () {
    for (final type in RelayMessageType.values) {
      final envelope = RelayEnvelope.create(
        type: type,
        body: const {'text': 'hello 🌍'},
      );
      final encoded = envelope.encode();

      expect(encoded, isA<List<int>>());
      expect(utf8.decode(encoded), contains('"version":1'));
      final decoded = RelayEnvelope.decode(encoded);
      expect(decoded.version, 1);
      expect(decoded.id, envelope.id);
      expect(decoded.type, type);
      expect(decoded.body, envelope.body);
    }
  });

  test('generated envelope IDs are non-empty and distinct', () {
    final ids = <String>{
      for (var i = 0; i < 100; i++)
        RelayEnvelope.create(type: RelayMessageType.chat, body: const {}).id,
    };
    expect(ids, hasLength(100));
    expect(ids.every((id) => id.isNotEmpty), isTrue);
  });

  test('end_chat is a versioned application envelope type', () {
    final encoded = RelayEnvelope.create(
      type: RelayMessageType.endChat,
      body: const {'reason': 'user_ended'},
    ).encode();
    final decoded = RelayEnvelope.decode(encoded);
    expect(decoded.version, 1);
    expect(decoded.type, RelayMessageType.endChat);
    expect(decoded.body, {'reason': 'user_ended'});
  });

  test('accepts exactly 256 encoded bytes and rejects 257', () {
    const id = 'x';
    final base = RelayEnvelope(
      id: id,
      type: RelayMessageType.chat,
      body: const {'text': ''},
    ).encode().length;
    final exactFit = RelayEnvelope(
      id: id,
      type: RelayMessageType.chat,
      body: {'text': List.filled(relayMaxMessageBytes - base, 'a').join()},
    ).encode();
    expect(exactFit, hasLength(relayMaxMessageBytes));
    expect(() => RelayEnvelope.decode(exactFit), returnsNormally);

    final tooLarge = RelayEnvelope(
      id: id,
      type: RelayMessageType.chat,
      body: {'text': List.filled(relayMaxMessageBytes - base + 1, 'a').join()},
    );
    expect(() => tooLarge.encode(), throwsFormatException);
    expect(() => RelayEnvelope.decode([...exactFit, 0]), throwsFormatException);
  });

  test('rejects malformed envelope structure, version, and message type', () {
    for (final json in [
      '{"version":1,"id":"x","type":"chat","body":[]}',
      '{"version":2,"id":"x","type":"chat","body":{}}',
      '{"version":1,"id":"x","type":"unknown","body":{}}',
      '{"version":1,"id":"","type":"chat","body":{}}',
      '{"version":1,"id":"x","type":"chat","body":{},"extra":1}',
    ]) {
      expect(
        () => RelayEnvelope.decode(utf8.encode(json)),
        throwsFormatException,
      );
    }
  });
}
