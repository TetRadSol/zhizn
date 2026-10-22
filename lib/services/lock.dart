import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/store.dart';

/// Вход по PIN. PIN хранится только как хеш и задаётся на каждом устройстве отдельно.
class Lock extends ChangeNotifier {
  Lock(this.store) : locked = store.getKv('pin') != null;

  final Store store;
  bool locked;
  DateTime? _pausedAt;
  int _wrong = 0;
  DateTime? blockedUntil;

  bool get enabled => store.getKv('pin') != null;

  String _hash(String pin) {
    var salt = store.getKv('pin_salt');
    if (salt == null) {
      final r = Random.secure();
      salt = base64Encode(List.generate(16, (_) => r.nextInt(256)));
      store.setKv('pin_salt', salt);
    }
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  void setPin(String? pin) {
    store.setKv('pin', pin == null ? null : _hash(pin));
    locked = false;
    notifyListeners();
  }

  bool check(String pin) => store.getKv('pin') == _hash(pin);

  /// Возвращает true, если PIN верный. После 5 ошибок — пауза 30 секунд.
  bool unlock(String pin) {
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil!)) return false;
    if (check(pin)) {
      locked = false;
      _wrong = 0;
      notifyListeners();
      return true;
    }
    if (++_wrong >= 5) {
      _wrong = 0;
      blockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    notifyListeners();
    return false;
  }

  /// Приложение ушло в фон.
  void paused() => _pausedAt ??= DateTime.now();

  /// Вернулись: если прошло больше минуты — снова спросить PIN.
  void resumed() {
    final at = _pausedAt;
    _pausedAt = null;
    if (enabled && at != null && DateTime.now().difference(at) > const Duration(minutes: 1)) {
      locked = true;
      notifyListeners();
    }
  }
}
