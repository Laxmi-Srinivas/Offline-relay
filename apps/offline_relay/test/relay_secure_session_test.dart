import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_relay/security/relay_secure_session.dart';

Future<(RelaySecureSession, RelaySecureSession)> _pairedSessions() async {
  final initiator = await RelaySecureSession.create(isInitiator: true);
  final responder = await RelaySecureSession.create(isInitiator: false);
  final initiatorPublicKey = await initiator.publicKeyBase64;
  final responderPublicKey = await responder.publicKeyBase64;
  await initiator.establish(responderPublicKey);
  await responder.establish(initiatorPublicKey);
  return (initiator, responder);
}

void main() {
  test(
    'authenticated encryption round trips with fresh session keys',
    () async {
      final (alice, bob) = await _pairedSessions();
      final frame = await alice.encrypt(
        utf8.encode('hello over encrypted BLE'),
      );

      expect(frame.counter, 0);
      expect(
        utf8.decode(
          await bob.decrypt(
            counter: frame.counter,
            ciphertext: frame.ciphertext,
          ),
        ),
        'hello over encrypted BLE',
      );

      final (newAlice, newBob) = await _pairedSessions();
      final newFrame = await newAlice.encrypt(
        utf8.encode('hello over encrypted BLE'),
      );
      expect(newFrame.ciphertext, isNot(frame.ciphertext));
      expect(
        utf8.decode(
          await newBob.decrypt(
            counter: newFrame.counter,
            ciphertext: newFrame.ciphertext,
          ),
        ),
        'hello over encrypted BLE',
      );
      alice.close();
      bob.close();
      newAlice.close();
      newBob.close();
    },
  );

  test('tampered ciphertext and invalid ciphertext are rejected', () async {
    final (alice, bob) = await _pairedSessions();
    final frame = await alice.encrypt(utf8.encode('private text'));
    final changed =
        String.fromCharCode(frame.ciphertext.codeUnitAt(0) == 65 ? 66 : 65) +
        frame.ciphertext.substring(1);
    await expectLater(
      bob.decrypt(counter: frame.counter, ciphertext: changed),
      throwsA(anything),
    );
    await expectLater(
      bob.decrypt(counter: frame.counter, ciphertext: 'not base64!'),
      throwsA(isA<FormatException>()),
    );
    alice.close();
    bob.close();
  });

  test('counter nonces advance and replayed frames are rejected', () async {
    final (alice, bob) = await _pairedSessions();
    final first = await alice.encrypt(utf8.encode('first'));
    final second = await alice.encrypt(utf8.encode('second'));
    expect(first.counter, 0);
    expect(second.counter, 1);

    expect(
      utf8.decode(
        await bob.decrypt(counter: first.counter, ciphertext: first.ciphertext),
      ),
      'first',
    );
    await expectLater(
      bob.decrypt(counter: first.counter, ciphertext: first.ciphertext),
      throwsA(isA<FormatException>()),
    );
    expect(
      utf8.decode(
        await bob.decrypt(
          counter: second.counter,
          ciphertext: second.ciphertext,
        ),
      ),
      'second',
    );
    alice.close();
    bob.close();
  });

  test('malformed and reflected key-exchange keys are rejected', () async {
    final alice = await RelaySecureSession.create(isInitiator: true);
    await expectLater(
      alice.establish('bad key'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      alice.establish(base64Url.encode(List<int>.filled(32, 0))),
      throwsA(isA<FormatException>()),
    );
    alice.close();
  });
}
