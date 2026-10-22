import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Шифрование обмена по Wi-Fi: поток из HMAC-SHA256 и проверка подлинности
/// (encrypt-then-MAC). Без ключа содержимое не прочитать и не подменить.
class Box {
  Box(List<int> key)
    : _enc = Hmac(sha256, Hmac(sha256, key).convert('enc'.codeUnits).bytes),
      _mac = Hmac(sha256, Hmac(sha256, key).convert('mac'.codeUnits).bytes);

  final Hmac _enc;
  final Hmac _mac;
  static final _rnd = Random.secure();

  static List<int> randomBytes(int n) => List.generate(n, (_) => _rnd.nextInt(256));

  Uint8List _xor(List<int> nonce, List<int> data) {
    final out = Uint8List(data.length);
    var block = <int>[];
    for (var i = 0; i < data.length; i++) {
      if (i % 32 == 0) {
        final c = i ~/ 32;
        block = _enc.convert([...nonce, c >> 24 & 255, c >> 16 & 255, c >> 8 & 255, c & 255]).bytes;
      }
      out[i] = data[i] ^ block[i % 32];
    }
    return out;
  }

  /// nonce(16) + шифротекст + метка(32)
  Uint8List seal(List<int> data) {
    final nonce = randomBytes(16);
    final ct = _xor(nonce, data);
    final tag = _mac.convert([...nonce, ...ct]).bytes;
    return Uint8List.fromList([...nonce, ...ct, ...tag]);
  }

  /// Возвращает null, если данные подменены или ключ не тот.
  Uint8List? open(List<int> sealed) {
    if (sealed.length < 48) return null;
    final nonce = sealed.sublist(0, 16);
    final ct = sealed.sublist(16, sealed.length - 32);
    final tag = sealed.sublist(sealed.length - 32);
    final want = _mac.convert([...nonce, ...ct]).bytes;
    var diff = 0;
    for (var i = 0; i < 32; i++) {
      diff |= want[i] ^ tag[i];
    }
    if (diff != 0) return null;
    return _xor(nonce, ct);
  }
}
