import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/store.dart';
import 'life.dart';

/// Доступ к Telegram Bot API. В тестах подменяется на поддельный чат.
abstract class TgApi {
  /// Вызвать метод; возвращает поле result. Ошибка Telegram — [TgError].
  Future<dynamic> call(String method, [Map<String, String> params = const {}]);

  /// Вызвать метод с файлом (sendDocument, editMessageMedia).
  Future<dynamic> upload(String method, Map<String, String> params, String field, String filename, List<int> bytes);

  /// Скачать файл по file_id.
  Future<List<int>> download(String fileId);
}

class TgError implements Exception {
  TgError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'Telegram $code: $message';
}

class HttpTgApi implements TgApi {
  HttpTgApi(this.token);
  final String token;

  Uri _u(String method) => Uri.parse('https://api.telegram.org/bot$token/$method');

  dynamic _result(http.Response r) {
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (j['ok'] != true) throw TgError((j['error_code'] as num?)?.toInt() ?? r.statusCode, '${j['description']}');
    return j['result'];
  }

  @override
  Future<dynamic> call(String method, [Map<String, String> params = const {}]) async =>
      _result(await http.post(_u(method), body: params).timeout(const Duration(seconds: 30)));

  @override
  Future<dynamic> upload(String method, Map<String, String> params, String field, String filename, List<int> bytes) async {
    final req = http.MultipartRequest('POST', _u(method))
      ..fields.addAll(params)
      ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
    final r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 90)));
    return _result(r);
  }

  @override
  Future<List<int>> download(String fileId) async {
    final f = await call('getFile', {'file_id': fileId}) as Map<String, dynamic>;
    final r = await http
        .get(Uri.parse('https://api.telegram.org/file/bot$token/${f['file_path']}'))
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw TgError(r.statusCode, 'не удалось скачать файл');
    return r.bodyBytes;
  }
}

/// Обмен изменениями через вашего личного Telegram-бота.
///
/// Устройство отправляет свои новые изменения файлом в чат с ботом (без звука).
/// Список всех таких файлов лежит в закреплённом сообщении «zhizn-index.json»:
/// устройство дописывает туда свои файлы и скачивает чужие, которые ещё не применяло.
/// Каждый раз устройство заново добавляет в список все свои файлы, поэтому, даже если
/// два устройства обновят список одновременно, пропавшая строка вернётся при следующем обмене.
class TgSyncEngine {
  TgSyncEngine(this.store, this.api, this.chatId, {required this.filesDir, this.captures = const []});

  final Store store;
  final TgApi api;
  final String chatId;
  final String filesDir;
  final List<Capture> captures;

  static const indexName = 'zhizn-index.json';

  List<Map<String, dynamic>> get _own =>
      ((jsonDecode(store.getKv('tg_own') ?? '[]') as List)).map((e) => (e as Map).cast<String, dynamic>()).toList();
  set _own(List<Map<String, dynamic>> v) => store.setKv('tg_own', jsonEncode(v));

  Future<Map<String, dynamic>> _send(String name, List<int> bytes) async {
    final m = await api.upload('sendDocument', {
      'chat_id': chatId,
      'disable_notification': 'true',
      'caption': name,
    }, 'document', name.split('/').last, bytes) as Map<String, dynamic>;
    return {'n': name, 'id': (m['document'] as Map)['file_id']};
  }

  Future<void> run() async {
    // 1. Отправить свои изменения
    final own = _own;
    final ops = store.pendingOps();
    for (var i = 0; i < ops.length; i += 2000) {
      final chunk = ops.sublist(i, i + 2000 > ops.length ? ops.length : i + 2000);
      final name = 'log/${store.device}/${chunk.first.ts}-${chunk.last.ts}.jsonl';
      final body = chunk.map((o) => jsonEncode(o.toJson())).join('\n');
      own.add(await _send(name, utf8.encode(body)));
      _own = own;
      store.markFileApplied(name);
      store.markPushed(chunk.map((o) => o.id));
    }
    // Вложения: фото, скриншоты, файлы (до 40 МБ — ограничение ботов 50 МБ)
    for (final c in captures.take(200)) {
      for (final f in c.files) {
        final name = 'files/${f['local']}';
        if (store.getKv('up:${f['local']}') != null) continue;
        final file = File('$filesDir/files/${f['local']}');
        if (!file.existsSync() || file.lengthSync() > 40 * 1024 * 1024) continue;
        own.add(await _send(name, await file.readAsBytes()));
        _own = own;
        store.setKv('up:${f['local']}', '1');
      }
    }

    // 2. Прочитать общий список файлов из закреплённого сообщения
    final chat = await api.call('getChat', {'chat_id': chatId}) as Map<String, dynamic>;
    final pinned = chat['pinned_message'] as Map<String, dynamic>?;
    final pinnedDoc = pinned?['document'] as Map<String, dynamic>?;
    var index = <Map<String, dynamic>>[];
    int? indexMsg;
    if (pinnedDoc != null && pinnedDoc['file_name'] == indexName) {
      indexMsg = (pinned!['message_id'] as num).toInt();
      final j = jsonDecode(utf8.decode(await api.download(pinnedDoc['file_id'] as String))) as Map<String, dynamic>;
      index = ((j['files'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    }

    // 3. Дописать свои файлы, если их там нет
    final names = index.map((e) => e['n']).toSet();
    final missing = own.where((e) => !names.contains(e['n'])).toList();
    if (missing.isNotEmpty || indexMsg == null) {
      final merged = [...index, ...missing];
      final bytes = utf8.encode(jsonEncode({'v': 1, 'files': merged}));
      if (indexMsg != null) {
        await api.upload('editMessageMedia', {
          'chat_id': chatId,
          'message_id': '$indexMsg',
          'media': jsonEncode({'type': 'document', 'media': 'attach://index'}),
        }, 'index', indexName, bytes);
      } else {
        final m = await api.upload('sendDocument', {
          'chat_id': chatId,
          'disable_notification': 'true',
          'caption': 'Список изменений «Жизни». Не открепляйте это сообщение.',
        }, 'document', indexName, bytes) as Map<String, dynamic>;
        await api.call('pinChatMessage', {
          'chat_id': chatId,
          'message_id': '${m['message_id']}',
          'disable_notification': 'true',
        });
      }
      index = merged;
    }

    // 4. Забрать чужие изменения и файлы
    final monthAgo = DateTime.now().subtract(const Duration(days: 31));
    final wantedFiles = {
      for (final c in captures)
        if (c.created.isAfter(monthAgo))
          for (final f in c.files) f['local'] as String,
    };
    final logs = index.where((e) => (e['n'] as String).startsWith('log/')).toList()
      ..sort((a, b) => (a['n'] as String).compareTo(b['n'] as String));
    for (final e in logs) {
      final name = e['n'] as String;
      if (store.isFileApplied(name)) continue;
      final text = utf8.decode(await api.download(e['id'] as String));
      store.applyRemote([
        for (final line in const LineSplitter().convert(text))
          if (line.trim().isNotEmpty) Op.fromJson(jsonDecode(line) as Map<String, dynamic>),
      ]);
      store.markFileApplied(name);
    }
    for (final e in index.where((e) => (e['n'] as String).startsWith('files/'))) {
      final local = (e['n'] as String).substring(6);
      final file = File('$filesDir/files/$local');
      if (!wantedFiles.contains(local) || file.existsSync()) continue;
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(await api.download(e['id'] as String));
      store.setKv('up:$local', '1');
    }
  }
}

/// Синхронизация телефона и ноутбука через Telegram: настройки, расписание обменов, статус.
class Sync extends ChangeNotifier {
  Sync(this.life, {TgApi Function(String token)? api}) : _api = api ?? HttpTgApi.new {
    life.store.addListener(_onLocalChange);
  }

  final Life life;
  final TgApi Function(String token) _api;
  Store get store => life.store;

  bool busy = false;
  String? lastError;
  DateTime? get lastOk => DateTime.tryParse(store.getKv('sync_ok') ?? '');
  Timer? _debounce;
  Timer? _periodic;

  String get token => store.getKv('tg_token') ?? '';
  String get chatId => store.getKv('tg_chat') ?? '';
  String get botName => store.getKv('tg_bot') ?? '';
  bool get configured => token.isNotEmpty && chatId.isNotEmpty;

  /// Проверить ключ бота и найти чат с вами (нужно перед этим написать боту).
  /// Возвращает текст ошибки или null.
  Future<String?> connect(String token) async {
    token = token.trim();
    final api = _api(token);
    try {
      final me = await api.call('getMe') as Map<String, dynamic>;
      final updates = (await api.call('getUpdates', {'limit': '100'}) as List).cast<Map<String, dynamic>>();
      String? chat;
      for (final u in updates.reversed) {
        final m = (u['message'] ?? u['edited_message']) as Map<String, dynamic>?;
        final c = m?['chat'] as Map<String, dynamic>?;
        if (c != null && c['type'] == 'private') {
          chat = '${c['id']}';
          break;
        }
      }
      if (chat == null) return 'Не вижу вашего сообщения. Откройте бота @${me['username']} в Telegram, нажмите «Старт» или напишите что угодно и попробуйте снова.';
      store.setKv('tg_token', token);
      store.setKv('tg_chat', chat);
      store.setKv('tg_bot', '${me['username']}');
      notifyListeners();
      return null;
    } on TgError catch (e) {
      return e.code == 401 || e.code == 404 ? 'Ключ бота не подходит. Скопируйте его из @BotFather целиком.' : 'Telegram: ${e.message}';
    } on SocketException {
      return 'Нет интернета';
    } on TimeoutException {
      return 'Telegram не отвечает';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  void disconnect() {
    store.setKv('tg_token', null);
    store.setKv('tg_chat', null);
    notifyListeners();
  }

  void start() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 10), (_) => run());
    run();
  }

  void _onLocalChange() {
    if (!configured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), run);
  }

  /// Один полный обмен: отправить своё, забрать чужое.
  Future<void> run() async {
    if (!configured || busy) return;
    busy = true;
    notifyListeners();
    try {
      await TgSyncEngine(store, _api(token), chatId, filesDir: life.filesDir, captures: life.captures).run();
      store.setKv('sync_ok', DateTime.now().toIso8601String());
      lastError = null;
    } on TgError catch (e) {
      lastError = e.code == 401 ? 'Ключ бота больше не действует' : 'Telegram: ${e.message}';
    } on SocketException {
      lastError = 'Нет интернета — синхронизирую позже';
    } on TimeoutException {
      lastError = 'Telegram не отвечает — синхронизирую позже';
    } catch (e) {
      lastError = 'Ошибка синхронизации: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    life.store.removeListener(_onLocalChange);
    super.dispose();
  }
}

/// Подписи для экрана настроек.
extension SyncInfo on Sync {
  int get pending => store.pendingOps().length;
  String get lastOkText {
    final t = lastOk;
    if (t == null) return 'ещё не было';
    final d = dayOf(t) == dayOf(DateTime.now()) ? 'сегодня' : '${t.day}.${t.month.toString().padLeft(2, '0')}';
    return '$d в ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
