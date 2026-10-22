import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/store.dart';
import 'life.dart';

/// Синхронизация через закрытый репозиторий GitHub.
///
/// Каждое устройство дописывает свои изменения новыми файлами в папку
/// `log/<устройство>/`. Файлы никогда не меняются, поэтому конфликтов нет:
/// устройство просто забирает чужие файлы, которые ещё не применяло.
class Sync extends ChangeNotifier {
  Sync(this.life) {
    life.store.addListener(_onLocalChange);
  }

  final Life life;
  Store get store => life.store;

  bool busy = false;
  String? lastError;
  DateTime? get lastOk => DateTime.tryParse(store.getKv('sync_ok') ?? '');
  Timer? _debounce;
  Timer? _periodic;

  String get repo => store.getKv('gh_repo') ?? '';
  String get token => store.getKv('gh_token') ?? '';
  bool get configured => repo.contains('/') && token.isNotEmpty;

  void configure(String repo, String token) {
    store.setKv('gh_repo', repo.trim().replaceFirst(RegExp(r'^https?://github.com/'), '').replaceAll(RegExp(r'/$'), ''));
    store.setKv('gh_token', token.trim());
    store.setKv('gh_branch', null);
    notifyListeners();
  }

  void disconnect() {
    store.setKv('gh_token', null);
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

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Uri _api(String path) => Uri.parse('https://api.github.com/repos/$repo$path');

  /// Проверить доступ. Возвращает текст ошибки или null.
  Future<String?> check() async {
    try {
      final r = await http.get(_api(''), headers: _headers).timeout(const Duration(seconds: 20));
      if (r.statusCode == 401) return 'Ключ не подходит. Создайте новый.';
      if (r.statusCode == 404) return 'Репозиторий не найден или ключ к нему не открыт.';
      if (r.statusCode != 200) return 'GitHub ответил ${r.statusCode}';
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['private'] != true) return 'Репозиторий открытый. Для данных нужен закрытый (Private).';
      final perms = (j['permissions'] as Map?) ?? const {};
      if (perms['push'] == false) return 'Ключ только читает. Дайте ему право Contents: Read and write.';
      store.setKv('gh_branch', (j['default_branch'] as String?) ?? 'main');
      return null;
    } on SocketException {
      return 'Нет интернета';
    } on TimeoutException {
      return 'GitHub не отвечает';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  /// Одна полная синхронизация: отправить своё, забрать чужое.
  Future<void> run() async {
    if (!configured || busy) return;
    busy = true;
    notifyListeners();
    try {
      if (store.getKv('gh_branch') == null) {
        final err = await check();
        if (err != null) throw _SyncError(err);
      }
      await _push();
      await _pull();
      store.setKv('sync_ok', DateTime.now().toIso8601String());
      lastError = null;
    } on _SyncError catch (e) {
      lastError = e.message;
    } on SocketException {
      lastError = 'Нет интернета — синхронизирую позже';
    } on TimeoutException {
      lastError = 'GitHub не отвечает — синхронизирую позже';
    } catch (e) {
      lastError = 'Ошибка синхронизации: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _put(String path, List<int> bytes, String message) async {
    final r = await http
        .put(
          _api('/contents/$path'),
          headers: _headers,
          body: jsonEncode({'message': message, 'content': base64Encode(bytes)}),
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 401) throw _SyncError('Ключ GitHub больше не действует');
    if (r.statusCode != 201 && r.statusCode != 200 && r.statusCode != 422) {
      throw _SyncError('Не удалось отправить изменения (${r.statusCode})');
    }
  }

  Future<void> _push() async {
    final ops = store.pendingOps();
    if (ops.isNotEmpty) {
      // Большие пачки делим, чтобы файл не вырос слишком сильно.
      for (var i = 0; i < ops.length; i += 2000) {
        final chunk = ops.sublist(i, i + 2000 > ops.length ? ops.length : i + 2000);
        final body = chunk.map((o) => jsonEncode(o.toJson())).join('\n');
        final path = 'log/${store.device}/${chunk.first.ts}-${chunk.last.ts}.jsonl';
        await _put(path, utf8.encode(body), '${store.device}: ${chunk.length} изменений');
        store.markFileApplied(path);
        store.markPushed(chunk.map((o) => o.id));
      }
    }
    // Вложения: фото, скриншоты, файлы
    for (final c in life.captures.take(200)) {
      for (final f in c.files) {
        final name = f['local'] as String;
        if (store.getKv('up:$name') != null) continue;
        final file = File(life.filePath(name));
        if (!file.existsSync()) continue;
        if (file.lengthSync() > 40 * 1024 * 1024) continue;
        await _put('files/$name', await file.readAsBytes(), 'файл ${f['name']}');
        store.setKv('up:$name', '1');
      }
    }
  }

  Future<void> _pull() async {
    final branch = store.getKv('gh_branch') ?? 'main';
    final r = await http
        .get(_api('/git/trees/$branch?recursive=1'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 409 || r.statusCode == 404) return; // пустой репозиторий
    if (r.statusCode != 200) throw _SyncError('Не удалось получить изменения (${r.statusCode})');
    final tree = ((jsonDecode(r.body) as Map)['tree'] as List).cast<Map<String, dynamic>>();

    final logs = tree
        .where((x) => x['type'] == 'blob' && (x['path'] as String).startsWith('log/'))
        .where((x) => !store.isFileApplied(x['path'] as String))
        .toList()
      ..sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    for (final x in logs) {
      final text = utf8.decode(await _blob(x['sha'] as String));
      final ops = <Op>[];
      for (final line in const LineSplitter().convert(text)) {
        if (line.trim().isEmpty) continue;
        ops.add(Op.fromJson(jsonDecode(line) as Map<String, dynamic>));
      }
      store.applyRemote(ops);
      store.markFileApplied(x['path'] as String);
    }

    // Скачать вложения с других устройств за последний месяц
    final remoteFiles = {
      for (final x in tree)
        if ((x['path'] as String).startsWith('files/')) (x['path'] as String).substring(6): x['sha'] as String,
    };
    final monthAgo = DateTime.now().subtract(const Duration(days: 31));
    for (final c in life.captures) {
      if (c.created.isBefore(monthAgo)) continue;
      for (final f in c.files) {
        final name = f['local'] as String;
        final file = File(life.filePath(name));
        if (file.existsSync() || !remoteFiles.containsKey(name)) continue;
        file.parent.createSync(recursive: true);
        await file.writeAsBytes(await _blob(remoteFiles[name]!));
        store.setKv('up:$name', '1');
      }
    }
  }

  Future<List<int>> _blob(String sha) async {
    final r = await http.get(_api('/git/blobs/$sha'), headers: _headers).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw _SyncError('Не удалось скачать изменения (${r.statusCode})');
    final c = (jsonDecode(r.body) as Map)['content'] as String;
    return base64Decode(c.replaceAll('\n', ''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    life.store.removeListener(_onLocalChange);
    super.dispose();
  }
}

class _SyncError implements Exception {
  _SyncError(this.message);
  final String message;
}

/// Сколько изменений ещё не отправлено — для подписи в настройках.
extension SyncInfo on Sync {
  int get pending => store.pendingOps().length;
  String get lastOkText {
    final t = lastOk;
    if (t == null) return 'ещё не было';
    final d = dayOf(t) == dayOf(DateTime.now()) ? 'сегодня' : '${t.day}.${t.month.toString().padLeft(2, '0')}';
    return '$d в ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
