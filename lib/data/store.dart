import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// Одна запись в базе: задача, привычка, запись из поля ввода и т. д.
///
/// Каждое поле хранит отметку «когда и с какого устройства изменено».
/// Так два устройства могут править одну запись: побеждает поздняя правка
/// поля, а все правки остаются в журнале.
class Entity {
  Entity(this.id, this.kind, this.f, this.stamps);

  final String id;
  final String kind;
  final Map<String, dynamic> f;
  final Map<String, String> stamps;

  bool get deleted => f['_del'] == true;
  dynamic operator [](String key) => f[key];
}

/// Изменение одного поля. Из таких изменений состоит журнал синхронизации.
class Op {
  Op({
    required this.id,
    required this.device,
    required this.ts,
    required this.entity,
    required this.kind,
    required this.field,
    required this.value,
  });

  final String id;
  final String device;
  final int ts;
  final String entity;
  final String kind;
  final String field;
  final dynamic value;

  String get stamp => '${ts.toString().padLeft(15, '0')}|$device';

  Map<String, dynamic> toJson() => {
    'id': id,
    'd': device,
    't': ts,
    'e': entity,
    'k': kind,
    'f': field,
    'v': value,
  };

  factory Op.fromJson(Map<String, dynamic> j) => Op(
    id: j['id'] as String,
    device: j['d'] as String,
    ts: (j['t'] as num).toInt(),
    entity: j['e'] as String,
    kind: j['k'] as String,
    field: j['f'] as String,
    value: j['v'],
  );
}

/// Локальная база устройства (SQLite) и журнал изменений.
class Store extends ChangeNotifier {
  Store(this.db, {String? deviceId, int Function()? clock})
    : _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _migrate();
    device = deviceId ?? getKv('device') ?? _newDeviceId();
    setKv('device', device);
    _load();
  }

  factory Store.open(String path, {String? deviceId}) =>
      Store(sqlite3.open(path), deviceId: deviceId);
  factory Store.memory({String? deviceId, int Function()? clock}) =>
      Store(sqlite3.openInMemory(), deviceId: deviceId, clock: clock);

  final Database db;
  final int Function() _now;
  late final String device;
  final Map<String, Entity> _all = {};
  int _clock = 0;
  final _rnd = Random();

  void _migrate() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS entities(
        id TEXT PRIMARY KEY, kind TEXT NOT NULL,
        data TEXT NOT NULL, stamps TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS ops(
        id TEXT PRIMARY KEY, device TEXT, ts INTEGER, entity TEXT,
        kind TEXT, field TEXT, value TEXT, pushed INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT);
      CREATE TABLE IF NOT EXISTS applied_files(path TEXT PRIMARY KEY);
    ''');
  }

  String _newDeviceId() {
    final p = defaultTargetPlatform == TargetPlatform.android ? 'tel' : 'pc';
    return '$p-${_rand(6)}';
  }

  String _rand(int n) {
    const a = 'abcdefghijkmnpqrstuvwxyz23456789';
    return List.generate(n, (_) => a[_rnd.nextInt(a.length)]).join();
  }

  void _load() {
    for (final r in db.select('SELECT * FROM entities')) {
      _all[r['id'] as String] = Entity(
        r['id'] as String,
        r['kind'] as String,
        Map<String, dynamic>.from(jsonDecode(r['data'] as String) as Map),
        Map<String, String>.from(jsonDecode(r['stamps'] as String) as Map),
      );
    }
    final m = db.select('SELECT MAX(ts) AS m FROM ops').first['m'];
    _clock = (m as int?) ?? 0;
  }

  // ---------- Чтение ----------

  Entity? get(String id) {
    final e = _all[id];
    return (e == null || e.deleted) ? null : e;
  }

  Iterable<Entity> ofKind(String kind) =>
      _all.values.where((e) => e.kind == kind && !e.deleted);

  // ---------- Запись ----------

  int _tick() {
    final now = _now();
    _clock = max(now, _clock + 1);
    return _clock;
  }

  String newId(String kind) =>
      '${kind.substring(0, min(2, kind.length))}${_now().toRadixString(36)}${_rand(4)}';

  String create(String kind, Map<String, dynamic> fields, {String? id}) {
    id ??= newId(kind);
    update(id, kind, {'created': DateTime.now().toIso8601String(), ...fields});
    return id;
  }

  void update(String id, String kind, Map<String, dynamic> fields) {
    final ops = <Op>[];
    for (final e in fields.entries) {
      ops.add(Op(
        id: '${device}_${_rand(8)}',
        device: device,
        ts: _tick(),
        entity: id,
        kind: kind,
        field: e.key,
        value: e.value,
      ));
    }
    _applyAll(ops, local: true);
  }

  /// Изменить поля существующей записи.
  void patch(String id, Map<String, dynamic> fields) {
    final e = _all[id];
    if (e == null) return;
    update(id, e.kind, fields);
  }

  void delete(String id) => patch(id, {'_del': true});
  void restore(String id) => patch(id, {'_del': false});

  /// Применить изменения с другого устройства.
  void applyRemote(List<Op> ops) => _applyAll(ops, local: false);

  void _applyAll(List<Op> ops, {required bool local}) {
    if (ops.isEmpty) return;
    final touched = <String>{};
    db.execute('BEGIN');
    try {
      final insertOp = db.prepare(
        'INSERT OR IGNORE INTO ops(id,device,ts,entity,kind,field,value,pushed) '
        'VALUES(?,?,?,?,?,?,?,?)',
      );
      for (final op in ops) {
        _clock = max(_clock, op.ts);
        insertOp.execute([
          op.id, op.device, op.ts, op.entity, op.kind, op.field,
          jsonEncode(op.value), local ? 0 : 1,
        ]);
        if (db.updatedRows == 0) continue; // уже применено
        final e = _all.putIfAbsent(
          op.entity,
          () => Entity(op.entity, op.kind, {}, {}),
        );
        final old = e.stamps[op.field];
        if (old == null || op.stamp.compareTo(old) > 0) {
          e.f[op.field] = op.value;
          e.stamps[op.field] = op.stamp;
          touched.add(op.entity);
        }
      }
      insertOp.close();
      final save = db.prepare(
        'INSERT OR REPLACE INTO entities(id,kind,data,stamps) VALUES(?,?,?,?)',
      );
      for (final id in touched) {
        final e = _all[id]!;
        save.execute([id, e.kind, jsonEncode(e.f), jsonEncode(e.stamps)]);
      }
      save.close();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    if (touched.isNotEmpty) notifyListeners();
  }

  // ---------- Синхронизация ----------

  List<Op> pendingOps() => db
      .select('SELECT * FROM ops WHERE pushed=0 ORDER BY ts')
      .map((r) => Op(
            id: r['id'] as String,
            device: r['device'] as String,
            ts: r['ts'] as int,
            entity: r['entity'] as String,
            kind: r['kind'] as String,
            field: r['field'] as String,
            value: jsonDecode(r['value'] as String),
          ))
      .toList();

  void markPushed(Iterable<String> opIds) {
    final s = db.prepare('UPDATE ops SET pushed=1 WHERE id=?');
    for (final id in opIds) {
      s.execute([id]);
    }
    s.close();
  }

  bool isFileApplied(String path) =>
      db.select('SELECT 1 FROM applied_files WHERE path=?', [path]).isNotEmpty;
  void markFileApplied(String path) =>
      db.execute('INSERT OR IGNORE INTO applied_files(path) VALUES(?)', [path]);

  /// История изменений записи (новые сверху).
  List<Op> history(String entityId) => db
      .select('SELECT * FROM ops WHERE entity=? ORDER BY ts DESC', [entityId])
      .map((r) => Op(
            id: r['id'] as String,
            device: r['device'] as String,
            ts: r['ts'] as int,
            entity: r['entity'] as String,
            kind: r['kind'] as String,
            field: r['field'] as String,
            value: jsonDecode(r['value'] as String),
          ))
      .toList();

  // ---------- Настройки этого устройства (не синхронизируются) ----------

  String? getKv(String key) {
    final r = db.select('SELECT value FROM kv WHERE key=?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  void setKv(String key, String? value) {
    if (value == null) {
      db.execute('DELETE FROM kv WHERE key=?', [key]);
    } else {
      db.execute('INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)', [key, value]);
    }
  }

  /// Сообщить экранам, что изменились настройки или внешние данные.
  void touch() => notifyListeners();
}
