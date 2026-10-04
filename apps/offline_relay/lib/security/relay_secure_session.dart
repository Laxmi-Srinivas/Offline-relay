import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Ephemeral X25519 session keys with AES-256-GCM and counter-based nonces.
/// Keys are established automatically; this does not authenticate peer identity.
final class RelaySecureSession {
  RelaySecureSession._({required this._isInitiator, required SimpleKeyPair key})
    : _keyPair = key;

  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aead = AesGcm.with256bits();

  final bool _isInitiator;
  SimpleKeyPair? _keyPair;
  SecretKey? _sendKey;
  SecretKey? _receiveKey;
  int _sendCounter = 0;
  int _lastReceiveCounter = -1;
  bool _closed = false;
  String? _publicKey;

  static Future<RelaySecureSession> create({required bool isInitiator}) async =>
      RelaySecureSession._(
        isInitiator: isInitiator,
        key: await _x25519.newKeyPair(),
      );

  Future<String> get publicKeyBase64 async {
    if (_closed) throw StateError('Session is closed.');
    if (_publicKey != null) return _publicKey!;
    final keyPair = _keyPair;
    if (_closed || keyPair == null) throw StateError('Session is closed.');
    final publicKey = await keyPair.extractPublicKey();
    return _publicKey = base64Url.encode(publicKey.bytes).replaceAll('=', '');
  }

  Future<void> establish(String remotePublicKeyBase64) async {
    if (_closed || _keyPair == null) throw StateError('Session is closed.');
    if (_sendKey != null) throw StateError('Key exchange already completed.');

    final List<int> remoteBytes;
    try {
      remoteBytes = base64Url.decode(
        base64Url.normalize(remotePublicKeyBase64),
      );
    } on FormatException {
      throw const FormatException('Invalid X25519 public key encoding.');
    }
    if (remoteBytes.length != 32) {
      throw const FormatException('X25519 public key must be 32 bytes.');
    }

    final localBytes = (await _keyPair!.extractPublicKey()).bytes;
    _publicKey = base64Url.encode(localBytes).replaceAll('=', '');
    if (_compareBytes(localBytes, remoteBytes) == 0) {
      throw const FormatException(
        'Peer key must be different from the local key.',
      );
    }
    final remotePublicKey = SimplePublicKey(
      remoteBytes,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: remotePublicKey,
    );
    if ((await sharedSecret.extractBytes()).every((byte) => byte == 0)) {
      throw const FormatException(
        'X25519 produced an invalid all-zero secret.',
      );
    }
    final orderedPublicKeys = _compareBytes(localBytes, remoteBytes) < 0
        ? <int>[...localBytes, ...remoteBytes]
        : <int>[...remoteBytes, ...localBytes];
    final salt = (await Sha256().hash(orderedPublicKeys)).bytes;

    final initiatorToResponder = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode('OfflineRelay/v1/initiator-to-responder'),
    );
    final responderToInitiator = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode('OfflineRelay/v1/responder-to-initiator'),
    );
    if (_closed) throw StateError('Session is closed.');
    _sendKey = _isInitiator ? initiatorToResponder : responderToInitiator;
    _receiveKey = _isInitiator ? responderToInitiator : initiatorToResponder;

    _keyPair = null;
  }

  Future<({int counter, String ciphertext})> encrypt(
    List<int> cleartext,
  ) async {
    final key = _sendKey;
    if (_closed || key == null) {
      throw StateError('Secure session is not ready.');
    }
    if (_sendCounter == 0xFFFFFFFFFFFFFFF) {
      throw StateError('Secure session message counter is exhausted.');
    }
    final counter = _sendCounter++;
    final nonce = _nonce(counter);
    final box = await _aead.encrypt(
      cleartext,
      secretKey: key,
      nonce: nonce,
      aad: _associatedData(counter, _isInitiator),
    );
    return (
      counter: counter,
      ciphertext: base64Url
          .encode(<int>[...box.cipherText, ...box.mac.bytes])
          .replaceAll('=', ''),
    );
  }

  Future<Uint8List> decrypt({
    required int counter,
    required String ciphertext,
  }) async {
    final key = _receiveKey;
    if (_closed || key == null) {
      throw StateError('Secure session is not ready.');
    }
    if (counter < 0 ||
        counter > 0xFFFFFFFFFFFFFFF ||
        counter <= _lastReceiveCounter) {
      throw const FormatException(
        'Repeated or invalid encrypted message counter.',
      );
    }

    final List<int> combined;
    try {
      combined = base64Url.decode(base64Url.normalize(ciphertext));
    } on FormatException {
      throw const FormatException('Invalid encrypted message encoding.');
    }
    if (combined.length < 16) {
      throw const FormatException('Encrypted message is incomplete.');
    }

    final box = SecretBox(
      combined.sublist(0, combined.length - 16),
      nonce: _nonce(counter),
      mac: Mac(combined.sublist(combined.length - 16)),
    );
    final cleartext = await _aead.decrypt(
      box,
      secretKey: key,
      aad: _associatedData(counter, !_isInitiator),
    );
    _lastReceiveCounter = counter;
    return Uint8List.fromList(cleartext);
  }

  void close() {
    _closed = true;
    _keyPair = null;
    _sendKey = null;
    _receiveKey = null;
    _publicKey = null;
  }

  static List<int> _nonce(int counter) {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint64(4, counter, Endian.big);
    return nonce;
  }

  static List<int> _associatedData(
    int counter,
    bool initiatorToResponder,
  ) => utf8.encode(
    'OfflineRelay/v1/secure-message/$counter/'
    '${initiatorToResponder ? 'initiator-to-responder' : 'responder-to-initiator'}',
  );

  static int _compareBytes(List<int> left, List<int> right) {
    for (var index = 0; index < left.length; index++) {
      final difference = left[index].compareTo(right[index]);
      if (difference != 0) return difference;
    }
    return 0;
  }
}






