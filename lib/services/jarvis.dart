import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../data/models.dart';
import '../data/store.dart';
import 'life.dart';

/// Что Джарвис сделал за один запуск — для ленты и уведомления.
class JarvisReport {
  int updated = 0;
  int created = 0;
  int questions = 0;
  int records = 0;
  bool evening = false;
  bool morning = false;
  String? focusTask;
  final List<String> rejected = [];

  String get summary {
    final parts = [
      if (records > 0) 'разобрано записей: $records',
      if (updated > 0) 'уточнено: $updated',
      if (created > 0) 'создано: $created',
      if (questions > 0) 'вопросов: $questions',
      if (evening) 'итог дня готов',
    ];
    return parts.isEmpty ? 'нового нет' : parts.join(', ');
  }
}

/// Сборка входных данных для Джарвиса и применение его ответа.
/// Без процессов и сети — проверяется автотестами.
class JarvisBrain {
  JarvisBrain(this.life);
  final Life life;
  Store get store => life.store;

  /// Записи, которые ещё не видел Джарвис (кроме помеченных «не в ИИ»).
  List<Capture> pendingRecords() => life.captures
      .where((c) => c.status == 'rules' && c.e['noAi'] != true)
      .toList()
      .reversed
      .take(30)
      .toList();

  List<Entity> pendingAnswers() =>
      store.ofKind(Kinds.question).where((q) => q['answer'] != null && q['used'] != true).toList();

  bool wantEvening(DateTime now) => now.hour >= 20 && life.digest(dayOf(now), 'evening') == null;

  bool hasWork(DateTime now) => pendingRecords().isNotEmpty || pendingAnswers().isNotEmpty || wantEvening(now);

  Map<String, dynamic> _task(Task t) => {
    'id': t.id,
    'title': t.title,
    if (t.notes.isNotEmpty) 'notes': t.notes,
    if (t.due != null) 'due': ymd(t.due!),
    'time': ?t.time,
    'dur': ?t.duration,
    'prio': ?t.prio,
    'sphere': ?t.sphere,
    'type': t.type,
    'energy': ?t.energy,
    'repeat': ?t.repeat,
    if (t.steps.isNotEmpty) 'steps': t.steps.map((s) => s['t']).toList(),
    'goal': ?t.e['goal'],
  };

  Map<String, dynamic> buildInput(DateTime now) {
    final today = dayOf(now);
    final records = pendingRecords();
    final evening = wantEvening(now);
    final tomorrow = today.add(const Duration(days: 1));
    return {
      'now': now.toIso8601String().substring(0, 16),
      'weekday': now.weekday,
      'profile': {for (final k in Life.profileDefaults.keys) k: life.profile(k)},
      'dictionary': life.dict,
      'schedule': {
        for (var i = 0; i < 8; i++)
          if (life.schedule.on(today.add(Duration(days: i))).isNotEmpty)
            ymd(today.add(Duration(days: i))): [
              for (final l in life.schedule.on(today.add(Duration(days: i))))
                '${l.start}-${l.end} ${l.subject}${l.type != null ? ' (${l.type})' : ''}${l.place != null ? ', ${l.place}' : ''}',
            ],
      },
      'busy': [for (final b in life.busy) {'title': b.title, 'from': ymd(b.from), 'to': ymd(b.to)}],
      'tasks': (life.tasks.where((t) => !t.done).toList()..sort(Life.compareTasks)).take(150).map(_task).toList(),
      'goals': [for (final g in life.goals) {'id': g.id, 'title': g['title'], 'measure': g['measure'], 'target': g['target'], 'due': g['due']}],
      'habits': [for (final h in life.habits) h.title],
      'records': [
        for (final c in records)
          {
            'id': c.id,
            'text': c.text,
            'at': c.created.toIso8601String().substring(0, 16),
            'made': [
              for (final id in c.results)
                if (store.get(id) case final e?)
                  e.kind == Kinds.task ? {'kind': 'task', ..._task(Task(e))} : {'kind': e.kind, 'id': id, ...e.f}..remove('created'),
            ],
            if (c.files.isNotEmpty)
              'files': [
                for (final f in c.files)
                  if (File(life.filePath(f['local'] as String)).existsSync()) 'files/${f['local']}',
              ],
          },
      ],
      'answers': [
        for (final q in pendingAnswers()) {'question': q['text'], 'answer': q['answer'], 'record': q['record'], 'task': q['task']},
      ],
      'want_evening': evening,
      'want_morning': evening,
      if (evening) ...{
        'day_stats': {
          'done': life.doneToday().map((t) => t.title).toList(),
          'not_done': life.todayTasks().map((t) => t.title).toList(),
          'habits': {for (final h in life.habits.where((h) => h.activeOn(today))) h.title: h.mark(today) ?? 'нет отметки'},
          'lessons': life.schedule.on(today).map((l) => '${l.subject}: ${life.lessonMark(l) ?? 'нет отметки'}').toList(),
        },
        'plan_tomorrow': [
          for (final s in life.dayPlan(tomorrow).slots)
            '${s.start.hour.toString().padLeft(2, '0')}:${s.start.minute.toString().padLeft(2, '0')} ${s.label}',
        ],
      },
    };
  }

  static const _taskFields = {'title', 'notes', 'due', 'time', 'dur', 'prio', 'sphere', 'type', 'energy', 'steps', 'goal', 'repeat'};
  static const _spheres = {'study', 'auto', 'health', 'self', 'hobby', 'home', 'money', 'personal'};

  /// Проверить поля от Джарвиса: всё лишнее и неверное отбрасывается.
  Map<String, dynamic>? _clean(Map<String, dynamic> f, List<String> rejected) {
    final out = <String, dynamic>{};
    for (final e in f.entries) {
      final v = e.value;
      bool ok = switch (e.key) {
        'title' || 'notes' => v is String,
        'due' => v == null || (v is String && parseYmd(v) != null),
        'time' => v == null || (v is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)),
        'dur' => v == null || (v is num && v > 0 && v <= 24 * 60),
        'prio' => v == null || const {'r', 'y', 'g'}.contains(v),
        'sphere' => v == null || _spheres.contains(v),
        'type' => const {'task', 'event', 'hw', 'deadline', 'shopping', 'question'}.contains(v),
        'energy' => v == null || const {'low', 'mid', 'high'}.contains(v),
        'steps' => v is List,
        'goal' => v == null || (v is String && store.get(v)?.kind == Kinds.goal),
        'repeat' => v == null || (v is Map && const {'d', 'w', 'a', 'm', 'y'}.contains(v['t'])),
        _ => false,
      };
      if (!_taskFields.contains(e.key)) ok = false;
      if (!ok) {
        rejected.add('${e.key}=$v');
        continue;
      }
      out[e.key] = switch (e.key) {
        'steps' => [for (final s in v as List) {'t': '$s', 'd': false}],
        'dur' => (v as num).round(),
        _ => v,
      };
    }
    return out.isEmpty ? null : out;
  }

  /// Достаёт JSON из ответа (на случай, если вокруг есть текст или ```json).
  static Map<String, dynamic>? extractJson(String text) {
    final a = text.indexOf('{'), b = text.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      return jsonDecode(text.substring(a, b + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  JarvisReport apply(Map<String, dynamic> out, DateTime now, {required Set<String> sentRecords, required Set<String> sentAnswers}) {
    final r = JarvisReport();
    final notesByRecord = <String, List<String>>{};
    for (final raw in (out['changes'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final c = raw.cast<String, dynamic>();
      final why = (c['why'] as String?)?.trim() ?? '';
      final fields = _clean(((c['fields'] as Map?) ?? const {}).cast<String, dynamic>(), r.rejected);
      if (fields == null) continue;
      if (c['op'] == 'update') {
        final e = store.get('${c['id']}');
        if (e == null || (e.kind != Kinds.task && e.kind != Kinds.goal)) {
          r.rejected.add('нет записи ${c['id']}');
          continue;
        }
        store.patch(e.id, {...fields, 'draft': false, 'jarvis': why.isEmpty ? 'уточнено Джарвисом' : why});
        r.updated++;
        final cap = e['capture'] as String?;
        if (cap != null && why.isNotEmpty) notesByRecord.putIfAbsent(cap, () => []).add('${e['title']}: $why');
      } else if (c['op'] == 'create') {
        final kind = switch (c['kind']) { 'note' => Kinds.note, 'goal' => Kinds.goal, _ => Kinds.task };
        if (fields['title'] is! String || (fields['title'] as String).trim().isEmpty) continue;
        final record = c['record'] as String?;
        final id = store.create(kind, {
          ...fields,
          if (kind == Kinds.task) 'type': fields['type'] ?? 'task',
          'jarvis': why.isEmpty ? 'создано Джарвисом' : why,
          if (record != null && store.get(record) != null) 'capture': record,
        });
        r.created++;
        if (record != null && store.get(record)?.kind == Kinds.capture) {
          final cap = Capture(store.get(record)!);
          store.patch(record, {'results': [...cap.results, id]});
          notesByRecord.putIfAbsent(record, () => []).add('+ ${fields['title']}${why.isNotEmpty ? ': $why' : ''}');
        }
      }
    }

    for (final raw in (out['questions'] as List?) ?? const []) {
      if (raw is! Map || raw['text'] is! String) continue;
      store.create(Kinds.question, {
        'text': raw['text'],
        if (raw['options'] is List) 'options': [for (final o in raw['options'] as List) '$o'],
        if (raw['record'] is String) 'record': raw['record'],
        if (raw['task'] is String && store.get(raw['task'] as String) != null) 'task': raw['task'],
      });
      r.questions++;
    }

    // Записи считаются разобранными, если Джарвис так сказал (или ничего не сказал, но ответ корректный)
    final done = ((out['records_done'] as List?) ?? sentRecords.toList()).map((x) => '$x').toSet().intersection(sentRecords);
    for (final id in done) {
      store.patch(id, {'status': 'jarvis', if (notesByRecord[id] != null) 'jarvisNotes': notesByRecord[id]});
      for (final t in Capture(store.get(id)!).results) {
        if (store.get(t)?.kind == Kinds.task && store.get(t)!['draft'] == true) store.patch(t, {'draft': false});
      }
    }
    r.records = done.length;
    for (final q in sentAnswers) {
      store.patch(q, {'used': true});
    }

    final today = dayOf(now);
    if (out['evening'] is String && (out['evening'] as String).trim().isNotEmpty) {
      store.update('digest:${ymd(today)}:evening', Kinds.digest, {'text': (out['evening'] as String).trim()});
      r.evening = true;
    }
    if (out['morning'] is String && (out['morning'] as String).trim().isNotEmpty) {
      final day = now.hour >= 12 ? today.add(const Duration(days: 1)) : today;
      store.update('digest:${ymd(day)}:morning', Kinds.digest, {'text': (out['morning'] as String).trim()});
      r.morning = true;
    }
    final fl = out['focus_lock'];
    if (fl is Map && fl['task'] is String && store.get(fl['task'] as String)?.kind == Kinds.task) {
      r.focusTask = fl['task'] as String;
      store.setKv('focus_suggest', jsonEncode({'task': fl['task'], 'reason': fl['reason'], 'day': ymd(today)}));
    }
    return r;
  }
}

/// Запуск Claude Code на ноутбуке по подписке. Только на Windows (и Linux для проверки).
class Jarvis extends ChangeNotifier {
  Jarvis(this.life);
  final Life life;
  late final brain = JarvisBrain(life);

  static bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool running = false;

  /// Вызывается после удачного разбора — чтобы показать уведомление.
  void Function(JarvisReport r)? onReport;
  String? lastError;
  Timer? _timer;
  String? _claude;

  /// Последний запуск: время и итог.
  /// Хранится в общей базе, чтобы и телефон видел, когда Джарвис разбирал записи.
  ({DateTime at, String text, bool ok})? get last => lastRun(life);

  static ({DateTime at, String text, bool ok})? lastRun(Life life) {
    final e = life.store.get('jarvis_status');
    final at = DateTime.tryParse((e?['at'] as String?) ?? '');
    if (e == null || at == null) return null;
    return (at: at, text: (e['text'] as String?) ?? '', ok: e['ok'] == true);
  }

  /// Время плановых запусков.
  List<String> get times => (life.store.getKv('jarvis_times') ?? '09:00,13:00,17:00,21:00').split(',').where((x) => x.isNotEmpty).toList();
  set times(List<String> v) {
    life.store.setKv('jarvis_times', (v..sort()).join(','));
    notifyListeners();
  }

  bool get enabled => life.store.getKv('jarvis_on') != '0';
  set enabled(bool v) {
    life.store.setKv('jarvis_on', v ? '1' : '0');
    notifyListeners();
  }

  String? get claudePathOverride => life.store.getKv('claude_path');
  set claudePathOverride(String? v) {
    life.store.setKv('claude_path', (v == null || v.trim().isEmpty) ? null : v.trim());
    _claude = null;
    notifyListeners();
  }

  void start() {
    if (!supported) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    if (!enabled || running) return;
    final now = DateTime.now();
    final hm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final lastRun = last?.at;
    final due = times.any((t) => t == hm) && (lastRun == null || now.difference(lastRun) > const Duration(minutes: 30));
    if (due && brain.hasWork(now)) run();
  }

  /// Найти Claude Code: путь из настроек, PATH, стандартные места установки.
  Future<String?> findClaude() async {
    if (_claude != null) return _claude;
    final o = claudePathOverride;
    if (o != null && File(o).existsSync()) return _claude = o;
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', ['claude']);
      if (r.exitCode == 0) {
        final lines = (r.stdout as String).split(RegExp(r'[\r\n]+')).where((l) => l.trim().isNotEmpty).toList();
        // На Windows предпочитаем .exe, затем .cmd
        lines.sort((a, b) => (b.endsWith('.exe') ? 1 : 0).compareTo(a.endsWith('.exe') ? 1 : 0));
        if (lines.isNotEmpty) return _claude = lines.first.trim();
      }
    } catch (_) {}
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    final appdata = Platform.environment['APPDATA'] ?? '';
    for (final c in [
      p.join(home, '.local', 'bin', Platform.isWindows ? 'claude.exe' : 'claude'),
      p.join(appdata, 'npm', 'claude.cmd'),
      p.join(home, '.claude', 'local', Platform.isWindows ? 'claude.exe' : 'claude'),
    ]) {
      if (File(c).existsSync()) return _claude = c;
    }
    return null;
  }

  void _saveLast(bool ok, String text) {
    life.store.update('jarvis_status', 'jstatus', {'at': DateTime.now().toIso8601String(), 'ok': ok, 'text': text});
  }

  /// Разобрать сейчас. Возвращает отчёт или null при ошибке (текст — в [lastError]).
  Future<JarvisReport?> run({bool force = false}) async {
    if (running) return null;
    final now = DateTime.now();
    if (!force && !brain.hasWork(now)) {
      lastError = null;
      _saveLast(true, 'нового нет');
      notifyListeners();
      return JarvisReport();
    }
    running = true;
    lastError = null;
    notifyListeners();
    try {
      final claude = await findClaude();
      if (claude == null) {
        throw _JarvisError('Не нашёл Claude Code. Установите его или укажите путь к claude.exe в настройках Джарвиса.');
      }
      final input = brain.buildInput(now);
      final sentRecords = {for (final r in input['records'] as List) (r as Map)['id'] as String};
      final sentAnswers = brain.pendingAnswers().map((q) => q.id).toSet();
      final dir = Directory(life.filesDir);
      await File(p.join(dir.path, 'input.json')).writeAsString(const JsonEncoder.withIndent(' ').convert(input));
      final prompt = await rootBundle.loadString('assets/jarvis_prompt.md');

      final proc = await Process.start(
        claude,
        ['-p', '--output-format', 'json', '--allowedTools', 'Read', '--max-turns', '20'],
        workingDirectory: dir.path,
        runInShell: claude.toLowerCase().endsWith('.cmd'),
      );
      proc.stdin.add(utf8.encode(prompt));
      await proc.stdin.close();
      final outF = proc.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      final errF = proc.stderr.fold<List<int>>([], (a, b) => a..addAll(b));
      final code = await proc.exitCode.timeout(const Duration(minutes: 15), onTimeout: () {
        proc.kill();
        return -1;
      });
      final stdout = utf8.decode(await outF, allowMalformed: true);
      final stderr = utf8.decode(await errF, allowMalformed: true);
      if (code == -1) throw _JarvisError('Claude Code не ответил за 15 минут');

      String result = stdout;
      try {
        final j = jsonDecode(stdout) as Map<String, dynamic>;
        result = (j['result'] as String?) ?? '';
        if (j['is_error'] == true) throw _JarvisError(_explain(result));
      } on FormatException {
        if (code != 0) throw _JarvisError(_explain('$stdout\n$stderr'));
      }
      final out = JarvisBrain.extractJson(result);
      if (out == null) throw _JarvisError('Джарвис ответил не по формату — попробую в следующий раз');
      final report = brain.apply(out, now, sentRecords: sentRecords, sentAnswers: sentAnswers);
      _saveLast(true, report.summary);
      onReport?.call(report);
      return report;
    } on _JarvisError catch (e) {
      lastError = e.message;
      _saveLast(false, e.message);
      return null;
    } catch (e) {
      lastError = 'Ошибка: $e';
      _saveLast(false, lastError!);
      return null;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  static String _explain(String text) {
    final l = text.toLowerCase();
    if (l.contains('limit') || l.contains('лимит')) return 'Лимит подписки на сейчас исчерпан — разберу при следующем запуске, пока работают правила';
    if (l.contains('login') || l.contains('auth') || l.contains('/login')) return 'Claude Code не вошёл в аккаунт: откройте терминал, выполните claude и войдите';
    final t = text.trim();
    return 'Claude Code: ${t.length > 200 ? t.substring(0, 200) : t}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _JarvisError implements Exception {
  _JarvisError(this.message);
  final String message;
}
