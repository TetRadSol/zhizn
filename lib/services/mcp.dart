import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/models.dart';
import '../logic/recurrence.dart';
import 'life.dart';

/// Коннектор для Claude Desktop (протокол MCP): Джарвис в чате видит и меняет
/// дела, расписание, привычки и ищет по всем записям.
///
/// Приложение отвечает на JSON-RPC по адресу http://127.0.0.1:47821/mcp (только с этого
/// компьютера), а Claude Desktop запускает маленький мост на PowerShell, который
/// пересылает туда строки из stdin.
class Mcp {
  Mcp(this.life);
  final Life life;

  static const _tools = [
    {
      'name': 'search',
      'description': 'Поиск по делам (и сделанным), заметкам, журналу и записям. Например: «автошкола» с from=2026-10-01, to=2026-10-31.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Слова для поиска'},
          'from': {'type': 'string', 'description': 'С даты ГГГГ-ММ-ДД (необязательно)'},
          'to': {'type': 'string', 'description': 'По дату ГГГГ-ММ-ДД (необязательно)'},
        },
        'required': ['query'],
      },
    },
    {
      'name': 'list_tasks',
      'description': 'Дела: today — просроченные и на сегодня, week — на 7 дней, all — все открытые, done — сделанные за 14 дней.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'scope': {'type': 'string', 'enum': ['today', 'week', 'all', 'done']},
          'sphere': {'type': 'string', 'description': 'study, auto, health, self, hobby, home, money, personal'},
        },
      },
    },
    {
      'name': 'add',
      'description': 'Записать текстом, как в поле записи приложения: «завтра в 15:00 вождение», «Практикум по ОРП», «обед 7,5». Можно несколько строк.',
      'inputSchema': {
        'type': 'object',
        'properties': {'text': {'type': 'string'}},
        'required': ['text'],
      },
    },
    {
      'name': 'update_task',
      'description': 'Изменить дело по id. Поля: title, notes, due (ГГГГ-ММ-ДД или null), time (ЧЧ:ММ или null), dur (мин), prio (r/y/g), sphere, energy (low/mid/high).',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'fields': {'type': 'object'},
        },
        'required': ['id', 'fields'],
      },
    },
    {
      'name': 'complete_task',
      'description': 'Отметить дело сделанным (у повторяющегося срок перейдёт на следующий раз).',
      'inputSchema': {
        'type': 'object',
        'properties': {'id': {'type': 'string'}},
        'required': ['id'],
      },
    },
    {
      'name': 'day',
      'description': 'День целиком: пары, план «что реально успеть», дела, привычки, итог Джарвиса. Без даты — сегодня.',
      'inputSchema': {
        'type': 'object',
        'properties': {'date': {'type': 'string', 'description': 'ГГГГ-ММ-ДД'}},
      },
    },
    {
      'name': 'habits',
      'description': 'Привычки: отметки за 7 дней, процент за 30 дней и серия.',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'mark_habit',
      'description': 'Отметить привычку: mark = ✓ (сделано), – (пропуск по причине), ✗ (не сделано) или пусто.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'habit': {'type': 'string', 'description': 'id или название привычки'},
          'date': {'type': 'string', 'description': 'ГГГГ-ММ-ДД, без даты — сегодня'},
          'mark': {'type': 'string', 'enum': ['✓', '–', '✗', '']},
        },
        'required': ['habit', 'mark'],
      },
    },
    {
      'name': 'profile_and_goals',
      'description': 'Профиль (кто я, места, принципы, тон) и цели.',
      'inputSchema': {'type': 'object', 'properties': {}},
    },
  ];

  /// Обработать одно JSON-RPC сообщение. null — ответ не нужен (уведомление).
  Map<String, dynamic>? handle(Map<String, dynamic> msg) {
    final id = msg['id'];
    final method = msg['method'] as String?;
    if (id == null) return null;
    Map<String, dynamic> ok(Object result) => {'jsonrpc': '2.0', 'id': id, 'result': result};
    switch (method) {
      case 'initialize':
        return ok({
          'protocolVersion': ((msg['params'] as Map?)?['protocolVersion'] as String?) ?? '2025-06-18',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'zhizn', 'title': 'Жизнь', 'version': '1'},
          'instructions': 'Это приложение «Жизнь»: дела, расписание пар, привычки, заметки. '
              'Ты — Джарвис, дружелюбный активный коуч. Перед ответом о планах вызови day или list_tasks. '
              'Ничего не удаляй.',
        });
      case 'ping':
        return ok({});
      case 'tools/list':
        return ok({'tools': _tools});
      case 'tools/call':
        final params = ((msg['params'] as Map?) ?? const {}).cast<String, dynamic>();
        try {
          final res = _call(params['name'] as String, ((params['arguments'] as Map?) ?? const {}).cast<String, dynamic>());
          return ok({
            'content': [{'type': 'text', 'text': const JsonEncoder.withIndent(' ').convert(res)}],
          });
        } catch (e) {
          return ok({
            'content': [{'type': 'text', 'text': 'Ошибка: $e'}],
            'isError': true,
          });
        }
      default:
        return {'jsonrpc': '2.0', 'id': id, 'error': {'code': -32601, 'message': 'Нет метода $method'}};
    }
  }

  Map<String, dynamic> _task(Task t) => {
    'id': t.id,
    'title': t.title,
    if (t.notes.isNotEmpty) 'notes': t.notes,
    if (t.due != null) 'due': ymd(t.due!),
    'time': ?t.time,
    'dur': ?t.duration,
    if (t.prio != null) 'prio': Prio.emoji(t.prio),
    if (t.sphere != null) 'sphere': Sphere.byId(t.sphere)?.label,
    if (t.repeat != null) 'repeat': Repeat.describe(t.repeat),
    if (t.done) 'done': t.doneAt?.toIso8601String().substring(0, 10) ?? true,
    if (t.steps.isNotEmpty) 'steps': t.steps.map((s) => '${s['d'] == true ? '✓' : '○'} ${s['t']}').toList(),
  };

  Object _call(String name, Map<String, dynamic> a) {
    final today = life.today;
    switch (name) {
      case 'search':
        final words = (a['query'] as String).toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).map((w) => w.length > 5 ? w.substring(0, w.length - 2) : w).toList();
        final from = parseYmd(a['from'] as String?), to = parseYmd(a['to'] as String?);
        bool inRange(String? iso) {
          final d = iso == null ? null : DateTime.tryParse(iso);
          if (d == null) return from == null && to == null;
          return (from == null || !d.isBefore(from)) && (to == null || !dayOf(d).isAfter(to));
        }

        bool match(String text) => words.every((w) => text.toLowerCase().contains(w));
        final out = <Map<String, dynamic>>[];
        for (final t in life.tasks) {
          final sphere = Sphere.byId(t.sphere)?.name ?? '';
          if (match('${t.title} ${t.notes} $sphere') && (inRange(t.due == null ? null : ymd(t.due!)) || inRange(t.e['created'] as String?))) {
            out.add({'kind': 'дело', ..._task(t)});
          }
        }
        for (final n in [...life.notes, ...life.journal]) {
          final text = '${n['title'] ?? n['text']}';
          if (match(text) && inRange(n['created'] as String?)) out.add({'kind': n.kind == Kinds.note ? 'заметка' : 'журнал', 'text': text, 'date': (n['created'] as String?)?.substring(0, 10)});
        }
        for (final c in life.captures) {
          if (match(c.text) && inRange(c.created.toIso8601String())) out.add({'kind': 'запись', 'text': c.text, 'date': ymd(c.created)});
        }
        return {'found': out.length, 'items': out.take(60).toList()};
      case 'list_tasks':
        final scope = (a['scope'] as String?) ?? 'today';
        var list = switch (scope) {
          'week' => life.tasks.where((t) => !t.done && t.due != null && !t.due!.isAfter(today.add(const Duration(days: 7)))),
          'all' => life.tasks.where((t) => !t.done),
          'done' => life.tasks.where((t) => t.done && t.doneAt != null && t.doneAt!.isAfter(today.subtract(const Duration(days: 14)))),
          _ => life.todayTasks(),
        }.toList()
          ..sort(Life.compareTasks);
        if (a['sphere'] != null) list = list.where((t) => t.sphere == a['sphere']).toList();
        return list.map(_task).toList();
      case 'add':
        final r = life.capture(a['text'] as String);
        return {
          'created': [
            for (final id in r.created)
              if (life.store.get(id) case final e?) e.kind == Kinds.task ? _task(Task(e)) : {'kind': e.kind, 'title': e['title'] ?? e['text']},
          ],
        };
      case 'update_task':
        final t = life.task(a['id'] as String);
        if (t == null) throw 'нет дела ${a['id']}';
        const allowed = {'title', 'notes', 'due', 'time', 'dur', 'prio', 'sphere', 'energy'};
        final f = (a['fields'] as Map).cast<String, dynamic>()..removeWhere((k, _) => !allowed.contains(k));
        if (f['due'] != null && parseYmd(f['due'] as String) == null) throw 'due должен быть ГГГГ-ММ-ДД';
        life.store.patch(t.id, {...f, 'draft': false, 'jarvis': 'изменено в чате с Джарвисом'});
        return _task(life.task(t.id)!);
      case 'complete_task':
        final t = life.task(a['id'] as String);
        if (t == null) throw 'нет дела ${a['id']}';
        life.complete(t);
        return _task(life.task(t.id)!);
      case 'day':
        final day = parseYmd(a['date'] as String?) ?? today;
        final plan = life.dayPlan(day);
        String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        return {
          'date': ymd(day),
          'busy': ?plan.busyReason,
          'lessons': [
            for (final l in life.schedule.on(day)) '${l.start}-${l.end} ${l.subject}${l.type != null ? ' (${l.type})' : ''} ${l.place ?? ''}'.trim(),
          ],
          'plan': [for (final s in plan.slots) '${hm(s.start)}-${hm(s.end)} ${s.label}'],
          'does_not_fit': plan.overflow.map((t) => t.title).toList(),
          'tasks': (day == today ? life.todayTasks() : life.tasks.where((t) => !t.done && t.due == day)).map(_task).toList(),
          'habits': {for (final h in life.habits.where((h) => h.activeOn(day))) h.title: h.mark(day) ?? '—'},
          'jarvis_evening': ?life.digest(day, 'evening')?['text'],
          'jarvis_morning': ?life.digest(day, 'morning')?['text'],
        };
      case 'habits':
        return [
          for (final h in life.habits)
            {
              'id': h.id,
              'title': h.title,
              'last7': [for (var i = 6; i >= 0; i--) h.mark(today.subtract(Duration(days: i))) ?? '·'].join(' '),
              'percent30': '${(h.percent(today) * 100).round()}% (цель ${h.target}%)',
              'streak': h.streak(today),
            },
        ];
      case 'mark_habit':
        final key = (a['habit'] as String).toLowerCase();
        final h = life.habits.where((h) => h.id == a['habit'] || h.title.toLowerCase().contains(key)).firstOrNull;
        if (h == null) throw 'нет привычки ${a['habit']}';
        final m = a['mark'] as String;
        life.setHabit(h, parseYmd(a['date'] as String?) ?? today, m.isEmpty ? null : m);
        return {'habit': h.title, 'mark': m};
      case 'profile_and_goals':
        return {
          'profile': {for (final k in Life.profileDefaults.keys) k: life.profile(k)},
          'goals': [for (final g in life.goals) {'title': g['title'], 'measure': g['measure'], 'target': g['target'], 'due': g['due']}],
        };
    }
    throw 'нет инструмента $name';
  }

  // ---------- Подключение к Claude Desktop ----------

  static const bridge = r'''# Мост «Жизнь» ↔ Claude Desktop: пересылает сообщения MCP в приложение «Жизнь».
$ErrorActionPreference = 'Continue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line) { break }
  if ($line.Trim() -eq '') { continue }
  try {
    $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:47821/mcp' -Method Post -UseBasicParsing `
      -Body ([Text.Encoding]::UTF8.GetBytes($line)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 60
    $ms = New-Object IO.MemoryStream
    $resp.RawContentStream.CopyTo($ms)
    $text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    if ($text.Trim() -ne '') { [Console]::Out.WriteLine($text); [Console]::Out.Flush() }
  } catch {
    try { $id = ($line | ConvertFrom-Json).id } catch { $id = $null }
    if ($null -ne $id) {
      $err = @{ jsonrpc = '2.0'; id = $id; error = @{ code = -32000; message = 'Приложение «Жизнь» на ноутбуке не запущено' } } | ConvertTo-Json -Compress -Depth 5
      [Console]::Out.WriteLine($err); [Console]::Out.Flush()
    }
  }
}
''';

  /// Записать мост и добавить «Жизнь» в настройки Claude Desktop. Возвращает текст ошибки или null.
  static Future<String?> connectClaudeDesktop(String filesDir) async {
    try {
      final script = File(p.join(filesDir, 'zhizn-mcp.ps1'));
      // BOM — чтобы Windows PowerShell 5 правильно прочитал русские буквы
      await script.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(bridge)]);
      final appdata = Platform.environment['APPDATA'];
      if (appdata == null) return 'Не нашёл папку настроек Windows (APPDATA)';
      final cfg = File(p.join(appdata, 'Claude', 'claude_desktop_config.json'));
      Map<String, dynamic> j = {};
      if (cfg.existsSync()) {
        final text = cfg.readAsStringSync();
        if (text.trim().isNotEmpty) j = jsonDecode(text) as Map<String, dynamic>;
        await cfg.copy('${cfg.path}.bak');
      } else {
        cfg.parent.createSync(recursive: true);
      }
      final servers = ((j['mcpServers'] as Map?) ?? {}).cast<String, dynamic>();
      servers['zhizn'] = {
        'command': 'powershell.exe',
        'args': ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path],
      };
      j['mcpServers'] = servers;
      await cfg.writeAsString(const JsonEncoder.withIndent('  ').convert(j));
      return null;
    } catch (e) {
      return 'Не получилось: $e';
    }
  }
}
