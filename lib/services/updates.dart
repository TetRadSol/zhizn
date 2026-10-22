import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Репозиторий с кодом. Сборка GitHub подставляет его сама.
const codeRepo = String.fromEnvironment('CODE_REPO', defaultValue: '');

class Update {
  Update(this.version, this.url, this.notes);
  final String version;
  final String url;
  final String notes;
}

/// Проверяет, вышла ли новая версия в разделе релизов GitHub.
class Updates extends ChangeNotifier {
  String current = '';
  Update? available;
  String? error;
  bool checking = false;

  Future<void> init() async {
    try {
      current = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    notifyListeners();
  }

  static List<int> _parse(String v) =>
      v.replaceFirst('v', '').split(RegExp(r'[.+-]')).take(3).map((x) => int.tryParse(x) ?? 0).toList();

  static bool newer(String a, String b) {
    final x = _parse(a), y = _parse(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  Future<void> check() async {
    if (codeRepo.isEmpty || checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final r = await http
          .get(Uri.parse('https://api.github.com/repos/$codeRepo/releases/latest'),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        error = r.statusCode == 404 ? 'Релизов пока нет' : 'GitHub ответил ${r.statusCode}';
        return;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = j['tag_name'] as String;
      final want = Platform.isAndroid ? '.apk' : '.exe';
      String? url;
      for (final a in (j['assets'] as List).cast<Map<String, dynamic>>()) {
        if ((a['name'] as String).endsWith(want)) url = a['browser_download_url'] as String;
      }
      available = (url != null && newer(tag, current)) ? Update(tag.replaceFirst('v', ''), url, (j['body'] as String?) ?? '') : null;
    } catch (_) {
      error = 'Нет связи с GitHub';
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// Скачать установщик: на телефоне откроется установка APK, на ноутбуке — мастер установки.
  Future<void> install() async {
    final u = available;
    if (u == null) return;
    await launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
  }
}
