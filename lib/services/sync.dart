import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/store.dart';
import 'lan_crypto.dart';
import 'life.dart';

const lanPort = 47821;
const lanDiscoveryPort = 47822;

/// Логика обмена без сети: что отправить и как применить ответ.
/// Отдельно от сокетов, чтобы проверять её автотестами.
class LanExchange {
  LanExchange(this.store, {required this.filesDir});
  final Store store;
  final String filesDir;

  int _cursor(String key) => int.tryParse(store.getKv(key) ?? '') ?? 0;

  /// Телефон: собрать запрос для ноутбука [peer].
  ({Map<String, dynamic> body, int sentUpTo}) request(String peer) {
    final mine = store.opsAfter(_cursor('lan_sent:$peer'), exceptDevice: peer);
    return (
      body: {
        'ops': mine.ops.map((o) => o.toJson()).toList(),
        'since': _cursor('lan_recv:$peer'),
        'files': localFiles(),
      },
      sentUpTo: mine.last,
    );
  }

  /// Ноутбук: принять изменения телефона [from] и отдать свои.
  Map<String, dynamic> serve(String from, Map<String, dynamic> body) {
    store.applyRemote([
      for (final o in (body['ops'] as List)) Op.fromJson((o as Map).cast<String, dynamic>()),
    ]);
    final theirs = store.opsAfter((body['since'] as num).toInt(), exceptDevice: from);
    return {
      'ops': theirs.ops.map((o) => o.toJson()).toList(),
      'cursor': theirs.last,
      'files': localFiles(),
      'more': theirs.last < store.lastRowid,
    };
  }

  /// Телефон: применить ответ ноутбука.
  void apply(String peer, Map<String, dynamic> resp, int sentUpTo) {
    store.applyRemote([
      for (final o in (resp['ops'] as List)) Op.fromJson((o as Map).cast<String, dynamic>()),
    ]);
    store.setKv('lan_recv:$peer', '${resp['cursor']}');
    store.setKv('lan_sent:$peer', '$sentUpTo');
  }

  /// Имена вложений, которые есть на этом устройстве.
  List<String> localFiles() {
    final d = Directory('$filesDir/files');
    if (!d.existsSync()) return const [];
    return d.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList();
  }
}

class LanPeer {
  LanPeer({required this.device, required this.name, required this.key, this.host, this.port = lanPort});
  final String device;
  final String name;
  final String key; // base64
  String? host;
  int port;

  Map<String, dynamic> toJson() => {'device': device, 'name': name, 'key': key, 'host': host, 'port': port};
  factory LanPeer.fromJson(Map<String, dynamic> j) => LanPeer(
    device: j['device'] as String,
    name: (j['name'] as String?) ?? '',
    key: j['key'] as String,
    host: j['host'] as String?,
    port: (j['port'] as num?)?.toInt() ?? lanPort,
  );

  Box get box => Box(base64Decode(key));
}

/// Найденный в сети ноутбук.
class Found {
  Found(this.device, this.name, this.host, this.port);
  final String device;
  final String name;
  final String host;
  final int port;
}

/// Синхронизация телефона и ноутбука напрямую по Wi-Fi.
///
/// Ноутбук всё время слушает домашнюю сеть. Телефон находит его, один раз
/// связывается по шестизначному коду и дальше сам обменивается изменениями,
/// когда оба в одной сети. Всё, что передаётся, зашифровано общим ключом.
class Sync extends ChangeNotifier {
  Sync(this.life, {bool? server}) : isServer = server ?? !Platform.isAndroid {
    life.store.addListener(_onLocalChange);
  }

  final Life life;
  Store get store => life.store;
  LanExchange get _x => LanExchange(store, filesDir: life.filesDir);

  /// Ноутбук принимает подключения, телефон подключается.
  final bool isServer;

  bool busy = false;
  String? lastError;
  DateTime? get lastOk => DateTime.tryParse(store.getKv('sync_ok') ?? '');
  Timer? _debounce;
  Timer? _periodic;
  HttpServer? _http;
  RawDatagramSocket? _udp;

  String get deviceName => isServer ? Platform.localHostname : 'Телефон';

  // ---------- Связанные устройства ----------

  Map<String, LanPeer> get peers {
    final raw = store.getKv('lan_peers');
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, LanPeer.fromJson((v as Map).cast<String, dynamic>())));
  }

  void _savePeers(Map<String, LanPeer> p) {
    store.setKv('lan_peers', jsonEncode(p.map((k, v) => MapEntry(k, v.toJson()))));
    notifyListeners();
  }

  bool get configured => peers.isNotEmpty;

  void unpair(String device) {
    final p = peers..remove(device);
    _savePeers(p);
  }

  // ---------- Запуск ----------

  void start() {
    if (isServer) {
      _serve();
    } else {
      _periodic?.cancel();
      _periodic = Timer.periodic(const Duration(minutes: 5), (_) => run());
      run();
    }
  }

  void _onLocalChange() {
    if (isServer || !configured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), run);
  }

  // ---------- Ноутбук: приём подключений ----------

  String? _code;
  DateTime? _codeUntil;

  /// Код для связи с телефоном, действует 10 минут.
  String pairingCode() {
    if (_code == null || DateTime.now().isAfter(_codeUntil!)) {
      _code = (100000 + Random.secure().nextInt(900000)).toString();
      _codeUntil = DateTime.now().add(const Duration(minutes: 10));
    }
    return _code!;
  }

  /// Адреса ноутбука в сети — на случай, если телефон не найдёт его сам.
  Future<List<String>> addresses() async {
    final out = <String>[];
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        if (!a.isLoopback) out.add(a.address);
      }
    }
    return out;
  }

  bool get serving => _http != null;

  Future<void> _serve() async {
    if (_http != null) return;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, lanPort, shared: true);
      _http!.listen(_handle);
      lastError = null;
    } catch (e) {
      lastError = 'Не удалось открыть порт $lanPort: $e';
    }
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, lanDiscoveryPort, reuseAddress: true);
      _udp!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = _udp!.receive();
        if (d == null || utf8.decode(d.data, allowMalformed: true) != 'ZHIZN?') return;
        final reply = utf8.encode('ZHIZN!${jsonEncode({'device': store.device, 'name': deviceName, 'port': lanPort})}');
        _udp!.send(reply, d.address, d.port);
      });
    } catch (e) {
      debugPrint('Поиск по сети недоступен: $e');
    }
    notifyListeners();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      final path = req.uri.path;
      if (path == '/pair' && req.method == 'POST') {
        return await _reply(req, utf8.encode(jsonEncode(_pair(jsonDecode(utf8.decode(body)) as Map<String, dynamic>))));
      }
      final peer = peers[req.headers.value('x-device')];
      if (peer == null) return await _reply(req, utf8.encode('{"error":"unknown"}'), status: 403);
      final box = peer.box;
      if (path == '/sync' && req.method == 'POST') {
        final open = box.open(body);
        if (open == null) return await _reply(req, const [], status: 403);
        final resp = _x.serve(peer.device, jsonDecode(utf8.decode(open)) as Map<String, dynamic>);
        store.setKv('sync_ok', DateTime.now().toIso8601String());
        lastError = null;
        notifyListeners();
        return await _reply(req, box.seal(utf8.encode(jsonEncode(resp))));
      }
      final name = req.uri.queryParameters['n'] ?? '';
      if (name.isEmpty || name.contains('/') || name.contains('\\') || name.contains('..')) {
        return await _reply(req, const [], status: 400);
      }
      final file = File('${life.filesDir}/files/$name');
      if (path == '/file' && req.method == 'GET') {
        if (!file.existsSync()) return await _reply(req, const [], status: 404);
        return await _reply(req, box.seal(await file.readAsBytes()));
      }
      if (path == '/file' && req.method == 'POST') {
        final open = box.open(body);
        if (open == null) return await _reply(req, const [], status: 403);
        file.parent.createSync(recursive: true);
        await file.writeAsBytes(open);
        return await _reply(req, const []);
      }
      return await _reply(req, const [], status: 404);
    } catch (e) {
      try {
        await _reply(req, utf8.encode('$e'), status: 500);
      } catch (_) {}
    }
  }

  Future<void> _reply(HttpRequest req, List<int> body, {int status = 200}) async {
    req.response.statusCode = status;
    req.response.add(body);
    await req.response.close();
  }

  /// Телефон доказывает, что знает код, и получает общий ключ (зашифрованный кодом).
  Map<String, dynamic> _pair(Map<String, dynamic> j) {
    final code = _code;
    if (code == null || DateTime.now().isAfter(_codeUntil!)) return {'error': 'Код устарел. Откройте на ноутбуке «Синхронизация» заново.'};
    final nonce = base64Decode(j['nonce'] as String);
    final device = j['device'] as String;
    final want = Hmac(sha256, utf8.encode(code)).convert([...nonce, ...utf8.encode(device)]).toString();
    if (want != j['proof']) return {'error': 'Неверный код'};
    final key = Box.randomBytes(32);
    final p = peers;
    p[device] = LanPeer(device: device, name: (j['name'] as String?) ?? 'Телефон', key: base64Encode(key));
    _savePeers(p);
    _code = null;
    final wrap = Box(sha256.convert([...utf8.encode(code), ...nonce]).bytes);
    return {'device': store.device, 'name': deviceName, 'key': base64Encode(wrap.seal(key))};
  }

  // ---------- Телефон: поиск, связь, обмен ----------

  /// Найти ноутбуки в этой сети (широковещательный запрос).
  Future<List<Found>> discover({Duration wait = const Duration(seconds: 2)}) async {
    final found = <String, Found>{};
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.broadcastEnabled = true;
      s.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = s!.receive();
        if (d == null) return;
        final t = utf8.decode(d.data, allowMalformed: true);
        if (!t.startsWith('ZHIZN!')) return;
        try {
          final j = jsonDecode(t.substring(6)) as Map<String, dynamic>;
          found[j['device'] as String] = Found(j['device'] as String, j['name'] as String, d.address.address, (j['port'] as num).toInt());
        } catch (_) {}
      });
      final msg = utf8.encode('ZHIZN?');
      for (var i = 0; i < 3; i++) {
        s.send(msg, InternetAddress('255.255.255.255'), lanDiscoveryPort);
        await Future.delayed(wait ~/ 3);
      }
    } catch (e) {
      debugPrint('Поиск не удался: $e');
    } finally {
      s?.close();
    }
    return found.values.toList();
  }

  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  Future<(int, List<int>)> _post(String host, int port, String path, List<int> body, {String? device, String method = 'POST'}) async {
    final req = await _client.openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path.split('?').first, query: path.contains('?') ? path.split('?').last : null));
    if (device != null) req.headers.set('x-device', device);
    if (method == 'POST') req.add(body);
    final resp = await req.close().timeout(const Duration(seconds: 60));
    final bytes = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
    return (resp.statusCode, bytes);
  }

  /// Связаться с ноутбуком по коду. Возвращает текст ошибки или null.
  Future<String?> pair(Found f, String code) async {
    code = code.replaceAll(RegExp(r'\D'), '');
    final nonce = Box.randomBytes(16);
    final proof = Hmac(sha256, utf8.encode(code)).convert([...nonce, ...utf8.encode(store.device)]).toString();
    try {
      final (status, body) = await _post(f.host, f.port, '/pair', utf8.encode(jsonEncode({
        'device': store.device,
        'name': deviceName,
        'nonce': base64Encode(nonce),
        'proof': proof,
      })));
      if (status != 200) return 'Ноутбук ответил $status';
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      if (j['error'] != null) return j['error'] as String;
      final wrap = Box(sha256.convert([...utf8.encode(code), ...nonce]).bytes);
      final key = wrap.open(base64Decode(j['key'] as String));
      if (key == null) return 'Неверный код';
      _savePeers({
        j['device'] as String: LanPeer(device: j['device'] as String, name: j['name'] as String, key: base64Encode(key), host: f.host, port: f.port),
      });
      unawaited(run());
      return null;
    } on SocketException {
      return 'Ноутбук не отвечает. Проверьте, что «Жизнь» на нём запущена и оба устройства в одной сети Wi-Fi';
    } on TimeoutException {
      return 'Ноутбук не отвечает';
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  /// Один обмен с ноутбуком. На ноутбуке ничего не делает — он ждёт телефон.
  Future<void> run() async {
    if (isServer || !configured) return;
    if (busy) {
      // Обмен уже идёт — повторить сразу после него
      _again ??= Completer<void>();
      return _again!.future;
    }
    busy = true;
    notifyListeners();
    final peer = peers.values.first;
    try {
      try {
        await _exchange(peer);
      } on SocketException {
        // Адрес ноутбука мог смениться — ищем заново
        final again = (await discover()).where((f) => f.device == peer.device).firstOrNull;
        if (again == null) throw const _NotHome();
        peer
          ..host = again.host
          ..port = again.port;
        _savePeers({peer.device: peer});
        await _exchange(peer);
      }
      store.setKv('sync_ok', DateTime.now().toIso8601String());
      lastError = null;
    } on _NotHome {
      lastError = 'Ноутбук не в этой сети — обменяюсь, когда будете дома';
    } on TimeoutException {
      lastError = 'Ноутбук не отвечает';
    } catch (e) {
      lastError = 'Ошибка синхронизации: $e';
    } finally {
      busy = false;
      notifyListeners();
      final again = _again;
      _again = null;
      if (again != null) unawaited(run().whenComplete(again.complete));
    }
  }

  Completer<void>? _again;

  Future<void> _exchange(LanPeer peer) async {
    final host = peer.host;
    if (host == null) throw const SocketException('нет адреса');
    final box = peer.box;
    final x = _x;
    Map<String, dynamic> resp;
    var rounds = 0;
    var sentAll = false;
    do {
      final r = x.request(peer.device);
      sentAll = r.sentUpTo >= store.lastRowid;
      final (status, body) = await _post(host, peer.port, '/sync', box.seal(utf8.encode(jsonEncode(r.body))), device: store.device);
      if (status == 403) throw Exception('ноутбук не узнал телефон — свяжите устройства заново');
      if (status != 200) throw Exception('ноутбук ответил $status');
      final open = box.open(body);
      if (open == null) throw Exception('ответ ноутбука не прошёл проверку');
      resp = jsonDecode(utf8.decode(open)) as Map<String, dynamic>;
      x.apply(peer.device, resp, r.sentUpTo);
    } while ((resp['more'] == true || !sentAll) && ++rounds < 50);

    // Вложения за последний месяц: недостающие забрать, свои отдать
    final theirs = ((resp['files'] as List?) ?? const []).cast<String>().toSet();
    final mine = x.localFiles().toSet();
    final monthAgo = DateTime.now().subtract(const Duration(days: 31));
    final wanted = {
      for (final c in life.captures)
        if (c.created.isAfter(monthAgo))
          for (final f in c.files) f['local'] as String,
    };
    for (final n in wanted) {
      final f = File('${life.filesDir}/files/$n');
      if (theirs.contains(n) && !mine.contains(n)) {
        final (status, body) = await _post(host, peer.port, '/file?n=${Uri.encodeQueryComponent(n)}', const [], device: store.device, method: 'GET');
        final open = status == 200 ? box.open(body) : null;
        if (open != null) {
          f.parent.createSync(recursive: true);
          await f.writeAsBytes(open);
        }
      } else if (mine.contains(n) && !theirs.contains(n)) {
        await _post(host, peer.port, '/file?n=${Uri.encodeQueryComponent(n)}', box.seal(await f.readAsBytes()), device: store.device);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    _http?.close(force: true);
    _udp?.close();
    life.store.removeListener(_onLocalChange);
    super.dispose();
  }
}

class _NotHome implements Exception {
  const _NotHome();
}

/// Подписи для экрана настроек.
extension SyncInfo on Sync {
  String get lastOkText {
    final t = lastOk;
    if (t == null) return 'ещё не было';
    final d = dayOf(t) == dayOf(DateTime.now()) ? 'сегодня' : '${t.day}.${t.month.toString().padLeft(2, '0')}';
    return '$d в ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
