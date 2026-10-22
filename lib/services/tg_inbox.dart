import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'life.dart';

/// Пересылка из Telegram: ноутбук раз в минуту забирает сообщения, которые вы
/// переслали своему боту, и превращает их в записи. Бот отвечает «Записано».
/// Принимаются сообщения только из чата владельца (кто первым написал /start).
class TgInbox extends ChangeNotifier {
  TgInbox(this.life);
  final Life life;
  Timer? _t;
  bool _busy = false;
  String? lastError;

  String get token => life.store.getKv('tg_inbox_token') ?? '';
  String? get owner => life.store.getKv('tg_inbox_owner');
  String? get bot => life.store.getKv('tg_inbox_bot');
  bool get enabled => token.isNotEmpty;

  Uri _u(String m) => Uri.parse('https://api.telegram.org/bot$token/$m');

  Future<dynamic> _call(String m, [Map<String, String> params = const {}]) async {
    final r = await http.post(_u(m), body: params).timeout(const Duration(seconds: 40));
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['ok'] != true) throw Exception(j['description']);
    return j['result'];
  }

  /// Подключить бота. Возвращает текст ошибки или null.
  Future<String?> connect(String t) async {
    life.store.setKv('tg_inbox_token', t.trim());
    try {
      final me = await _call('getMe') as Map<String, dynamic>;
      life.store.setKv('tg_inbox_bot', '${me['username']}');
      life.store.setKv('tg_inbox_owner', null);
      start();
      notifyListeners();
      return null;
    } catch (e) {
      life.store.setKv('tg_inbox_token', null);
      notifyListeners();
      return 'Ключ не подходит: $e';
    }
  }

  void disconnect() {
    life.store.setKv('tg_inbox_token', null);
    _t?.cancel();
    notifyListeners();
  }

  void start() {
    _t?.cancel();
    if (!enabled) return;
    _t = Timer.periodic(const Duration(minutes: 1), (_) => poll());
    poll();
  }

  Future<void> poll() async {
    if (!enabled || _busy) return;
    _busy = true;
    try {
      final offset = int.tryParse(life.store.getKv('tg_inbox_offset') ?? '') ?? 0;
      final updates = (await _call('getUpdates', {'offset': '$offset', 'timeout': '0'}) as List).cast<Map<String, dynamic>>();
      for (final u in updates) {
        life.store.setKv('tg_inbox_offset', '${(u['update_id'] as num).toInt() + 1}');
        final m = u['message'] as Map<String, dynamic>?;
        if (m == null) continue;
        final chat = '${(m['chat'] as Map)['id']}';
        if (owner == null) life.store.setKv('tg_inbox_owner', chat);
        if (chat != owner) continue;
        var text = ((m['text'] ?? m['caption']) as String?) ?? '';
        if (text == '/start') {
          await _call('sendMessage', {'chat_id': chat, 'text': 'Привет! Пересылайте сюда сообщения, фото и файлы — они появятся в «Жизни» на ноутбуке.'});
          continue;
        }
        final from = (m['forward_origin'] as Map?)?['sender_user']?['first_name'] ?? (m['forward_origin'] as Map?)?['sender_user_name'] ?? (m['forward_origin'] as Map?)?['chat']?['title'];
        if (from != null) text = '$text\n(переслано от $from)';
        final files = <String>[];
        final photo = (m['photo'] as List?)?.cast<Map>().lastOrNull;
        final doc = m['document'] as Map?;
        final fileId = (photo ?? doc)?['file_id'] as String?;
        if (fileId != null) {
          final f = await _call('getFile', {'file_id': fileId}) as Map<String, dynamic>;
          final r = await http.get(Uri.parse('https://api.telegram.org/file/bot$token/${f['file_path']}')).timeout(const Duration(seconds: 60));
          final name = (doc?['file_name'] as String?) ?? 'telegram_${DateTime.now().millisecondsSinceEpoch}${p.extension(f['file_path'] as String)}';
          final tmp = File(p.join(Directory.systemTemp.path, name));
          await tmp.writeAsBytes(r.bodyBytes);
          files.add(tmp.path);
        }
        if (text.trim().isEmpty && files.isEmpty) continue;
        final res = life.capture(text.trim(), files: files);
        await _call('sendMessage', {
          'chat_id': chat,
          'text': res.created.isEmpty ? 'Записано ✓ Джарвис разберёт при следующем разборе' : 'Записано ✓ (${res.created.length})',
          'reply_to_message_id': '${m['message_id']}',
        });
      }
      lastError = null;
    } catch (e) {
      lastError = '$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
