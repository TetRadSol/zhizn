import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/models.dart';
import '../data/store.dart';
import '../logic/parser.dart';
import '../logic/planner.dart';
import '../logic/recurrence.dart';
import '../logic/schedule.dart';

/// Итог одной записи: что создано, чтобы показать и при необходимости отменить.
class CaptureResult {
  CaptureResult(this.captureId, this.created);
  final String captureId;
  final List<String> created;
}

/// Всё, что приложение делает с данными. Экраны вызывают только его.
class Life extends ChangeNotifier {
  Life(this.store, {required this.filesDir}) {
    store.addListener(notifyListeners);
    _loadSchedule();
  }

  final Store store;
  final String filesDir;
  Schedule schedule = Schedule.empty('3102');
  List<String> scheduleChanges = const [];

  DateTime get now => DateTime.now();
  DateTime get today => dayOf(now);

  // ---------- Настройки ----------

  String get group => store.getKv('group') ?? '3102';
  set group(String g) {
    store.setKv('group', g);
    _loadSchedule();
    refreshSchedule();
  }

  /// Словарь сокращений: «спортмасс» → сфера. Синхронизируется.
  Map<String, String> get dict {
    final e = store.get('dict');
    if (e == null) return {};
    return {
      for (final x in e.f.entries)
        if (x.key.startsWith('a:') && x.value is String && (x.value as String).isNotEmpty)
          x.key.substring(2): x.value as String,
    };
  }

  void setDictWord(String word, String? sphere) {
    final w = word.trim().toLowerCase();
    if (w.isEmpty) return;
    store.update('dict', Kinds.dict, {'a:$w': sphere ?? ''});
  }

  // ---------- Запись ----------

  Parser parser() => Parser(now: now, schedule: schedule, dict: dict);

  CaptureResult capture(String text, {List<String> files = const []}) {
    final items = text.trim().isEmpty ? <Parsed>[] : parser().parse(text);
    final created = <String>[];
    final captureId = store.newId(Kinds.capture);
    for (final it in items) {
      switch (it.kind) {
        case 'habit':
          created.add(store.create(Kinds.habit, {
            'title': it.title,
            'sphere': ?it.sphere,
            'order': habits.length,
          }));
        case 'goal':
          created.add(store.create(Kinds.goal, {'title': it.title, 'sphere': ?it.sphere}));
        case 'note':
          created.add(store.create(Kinds.note, {
            'title': it.title,
            'type': it.type,
            'sphere': ?it.sphere,
            'capture': captureId,
          }));
        case 'journal':
          created.add(store.create(Kinds.journal, {
            'text': it.title,
            'type': it.type,
            'amount': ?it.amount,
            'date': ymd(today),
            'sphere': ?it.sphere,
          }));
        default:
          created.add(store.create(Kinds.task, {
            ...it.toTaskFields(),
            'draft': true,
            'capture': captureId,
          }));
      }
    }
    final saved = <Map<String, dynamic>>[];
    for (final f in files) {
      saved.add(_saveFile(f, captureId));
    }
    store.create(Kinds.capture, {
      'text': text.trim(),
      'results': created,
      'why': [for (final it in items) it.why.join(' · ')],
      'files': saved,
      'status': 'rules',
    }, id: captureId);
    return CaptureResult(captureId, created);
  }

  Map<String, dynamic> _saveFile(String path, String captureId) {
    final dir = Directory(p.join(filesDir, 'files'))..createSync(recursive: true);
    final name = '${captureId}_${p.basename(path)}';
    final dest = p.join(dir.path, name);
    try {
      File(path).copySync(dest);
    } catch (_) {}
    return {'name': p.basename(path), 'local': name};
  }

  String filePath(String localName) => p.join(filesDir, 'files', localName);

  void undoCapture(CaptureResult r) {
    for (final id in r.created) {
      store.delete(id);
    }
    store.delete(r.captureId);
  }

  // ---------- Чтение ----------

  List<Task> get tasks => store.ofKind(Kinds.task).map(Task.new).toList();
  List<Habit> get habits =>
      store.ofKind(Kinds.habit).map(Habit.new).toList()..sort((a, b) => a.order.compareTo(b.order));
  List<Capture> get captures =>
      store.ofKind(Kinds.capture).map(Capture.new).toList()..sort((a, b) => b.created.compareTo(a.created));
  List<Entity> get goals => store.ofKind(Kinds.goal).toList();
  List<Entity> get notes => store.ofKind(Kinds.note).toList();
  List<Entity> get journal => store.ofKind(Kinds.journal).toList();

  // ---------- Профиль Джарвиса ----------

  static const profileDefaults = <String, String>{
    'about': 'Студент 4-го курса, группа 3102 (ФКМ). С 8:00 до 16:00 телефон сдан. '
        'Учусь в автошколе. Распорядок может смениться в последний момент: наряды, сборы.',
    'places': 'Дом, ВУЗ, ночёвка в ВУЗе (наряд), город, автошкола, дача, зал. Пара — ВУЗ, наряд — ночёвка в ВУЗе.',
    'principles': 'Делать как можно раньше: ставить дело в ближайшее свободное окно, а не к сроку. '
        'Оставлять запас на неожиданное. Сначала срочное и важное.',
    'goals': 'Закрыть сессию без долгов, получить права, накопить 1000 Br, 100 часов самостоятельной учёбы, иностранный язык.',
    'tone': 'Дружелюбный активный коуч: замечает, подталкивает, хвалит. Мотивирует, в том числе показывая, '
        'что будет, если не сделать, — но без упрёков. Подсказывает порядок дел, опрашивая меня. '
        'Даёт ссылки на короткие видео, как правильно делать.',
    'wake': '06:30',
    'sleep': '23:00',
    'road': '30',
  };

  String profile(String key) {
    final v = store.get('profile')?[key];
    return (v is String && v.isNotEmpty) ? v : (profileDefaults[key] ?? '');
  }

  void setProfile(String key, String value) => store.update('profile', Kinds.profile, {key: value});

  // ---------- Форс-мажор ----------

  List<({String id, DateTime from, DateTime to, String title})> get busy => [
    for (final e in store.ofKind(Kinds.busy))
      if (parseYmd(e['from'] as String?) != null && parseYmd(e['to'] as String?) != null)
        (id: e.id, from: parseYmd(e['from'] as String)!, to: parseYmd(e['to'] as String)!, title: (e['title'] as String?) ?? 'Занят'),
  ];

  /// Текущий форс-мажор, если сегодня занят.
  ({String id, DateTime from, DateTime to, String title})? get busyNow {
    for (final b in busy) {
      if (!b.from.isAfter(today) && !b.to.isBefore(today)) return b;
    }
    return null;
  }

  /// Отметить дни занятыми и перенести на день после них дела со сроком внутри.
  /// Возвращает перенесённые задачи.
  List<Task> forceMajeure(String title, DateTime from, DateTime to) {
    store.create(Kinds.busy, {'title': title, 'from': ymd(from), 'to': ymd(to)});
    final after = dayOf(to).add(const Duration(days: 1));
    final moved = <Task>[];
    for (final t in tasks) {
      final d = t.due;
      if (t.done || d == null || d.isBefore(dayOf(from)) || d.isAfter(dayOf(to)) || t.repeat != null) continue;
      store.patch(t.id, {'due': ymd(after), 'time': null, 'jarvis': 'перенесено: $title'});
      moved.add(t);
    }
    return moved;
  }

  // ---------- План дня ----------

  DayRules get dayRules => DayRules(
    wake: profile('wake'),
    sleep: profile('sleep'),
    campusFrom: store.getKv('quiet_from') ?? '08:00',
    campusTo: store.getKv('quiet_to') ?? '16:00',
    campusDays: (store.getKv('quiet_days') ?? '1,2,3,4,5,6').split(',').where((x) => x.isNotEmpty).map(int.parse).toList(),
    road: int.tryParse(profile('road')) ?? 30,
  );

  DayPlan dayPlan([DateTime? day]) => planDay(
    day: day ?? today,
    now: now,
    tasks: tasks,
    lessons: schedule.on(day ?? today),
    busy: [for (final b in busy) (from: b.from, to: b.to, title: b.title)],
    rules: dayRules,
  );

  // ---------- Вопросы и итоги Джарвиса ----------

  List<Entity> get openQuestions =>
      store.ofKind(Kinds.question).where((q) => q['answer'] == null && q['skipped'] != true).toList()
        ..sort((a, b) => ((a['created'] as String?) ?? '').compareTo((b['created'] as String?) ?? ''));

  void answer(String questionId, String text) =>
      store.patch(questionId, {'answer': text, 'answeredAt': DateTime.now().toIso8601String()});

  Entity? digest(DateTime day, String kind) => store.get('digest:${ymd(day)}:$kind');

  static int compareTasks(Task a, Task b) {
    final ad = a.due, bd = b.due;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
    final at = a.time, bt = b.time;
    if (at != null && bt != null && at != bt) return at.compareTo(bt);
    if ((at == null) != (bt == null)) return at == null ? 1 : -1;
    return Prio.rank(a.prio).compareTo(Prio.rank(b.prio));
  }

  /// Дела на сегодня: просроченные и на сегодня, ещё не сделанные.
  List<Task> todayTasks() {
    final t = today;
    return tasks.where((x) => !x.done && x.due != null && !x.due!.isAfter(t)).toList()
      ..sort(compareTasks);
  }

  /// Сделано сегодня (включая выполненные повторы).
  List<Task> doneToday() {
    final t = today;
    return tasks
        .where((x) => x.completedOn(t) || (x.done && x.doneAt != null && dayOf(x.doneAt!) == t))
        .toList();
  }

  /// Прогресс дня: пары, которые уже прошли и не отмечены как пропуск, и дела.
  ({int done, int total}) dayProgress() {
    final lessons = schedule.on(today);
    var done = 0;
    for (final l in lessons) {
      final m = lessonMark(l);
      if (m == '✓' || m == '–' || (m == null && l.endAt.isBefore(now))) done++;
    }
    final doneTasks = doneToday().length;
    final open = todayTasks().length;
    return (done: done + doneTasks, total: lessons.length + doneTasks + open);
  }

  // ---------- Действия с задачами ----------

  Task? task(String id) {
    final e = store.get(id);
    return e == null ? null : Task(e);
  }

  /// Отметить выполненной. У повторяющейся задачи срок переходит на следующий раз.
  void complete(Task t) {
    final rep = t.repeat;
    if (rep != null && t.due != null) {
      final next = Repeat.next(rep, t.due!, now, doneCount: t.doneCount);
      store.patch(t.id, {
        'c:${ymd(today)}': true,
        'doneCount': t.doneCount + 1,
        'draft': false,
        if (next != null) 'due': ymd(next) else ...{'done': true, 'doneAt': now.toIso8601String()},
      });
    } else {
      store.patch(t.id, {'done': true, 'doneAt': now.toIso8601String(), 'draft': false});
    }
  }

  /// Отменить отметку о выполнении.
  void uncomplete(Task t) {
    final key = 'c:${ymd(today)}';
    if (t.e[key] == true && t.repeat != null) {
      // вернуть повтор на сегодня
      store.patch(t.id, {key: false, 'doneCount': (t.doneCount - 1).clamp(0, 1 << 30), 'due': ymd(today), 'done': false});
    } else {
      store.patch(t.id, {'done': false, 'doneAt': null});
    }
  }

  void moveTo(Task t, DateTime? day) =>
      store.patch(t.id, {'due': day == null ? null : ymd(day), 'draft': false});

  // ---------- Привычки ----------

  static const marks = [null, '✓', '–', '✗'];

  void cycleHabit(Habit h, DateTime day) {
    final i = marks.indexOf(h.mark(day));
    store.patch(h.id, {'m:${ymd(day)}': marks[(i + 1) % marks.length]});
  }

  void setHabit(Habit h, DateTime day, String? mark) =>
      store.patch(h.id, {'m:${ymd(day)}': mark});

  // ---------- Пары ----------

  String? lessonMark(Lesson l) => store.get('lesson:${l.ref}')?['att'] as String?;

  void cycleLesson(Lesson l) {
    final i = marks.indexOf(lessonMark(l));
    store.update('lesson:${l.ref}', Kinds.lesson, {'att': marks[(i + 1) % marks.length]});
  }

  List<Task> tasksForLesson(Lesson l) =>
      tasks.where((t) => t.lessonRef == l.ref).toList();

  // ---------- Расписание ----------

  static const scheduleUrls = [
    'https://fkm2023-oss.github.io/raspisanie-fkm-26/',
    'https://raw.githubusercontent.com/fkm2023-oss/raspisanie-fkm-26/main/index.html',
  ];

  DateTime? get scheduleFetched => DateTime.tryParse(store.getKv('schedule_at') ?? '');

  void _loadSchedule() {
    final raw = store.getKv('schedule_data');
    if (raw == null) {
      schedule = Schedule.empty(group);
      return;
    }
    try {
      schedule = Schedule.fromData(jsonDecode(raw) as Map<String, dynamic>, group);
    } catch (_) {
      schedule = Schedule.empty(group);
    }
  }

  /// Забрать расписание с сайта. Возвращает текст ошибки или null.
  Future<String?> refreshSchedule() async {
    String? error;
    for (final url in scheduleUrls) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) {
          error = 'Сайт ответил ${r.statusCode}';
          continue;
        }
        final data = Schedule.extractData(utf8.decode(r.bodyBytes));
        final fresh = Schedule.fromData(data, group);
        if (fresh.byDate.isEmpty) return 'На сайте нет группы $group';
        final old = schedule;
        scheduleChanges = old.byDate.isEmpty
            ? const []
            : old.changedDays(fresh).where((d) => !parseYmd(d)!.isBefore(today)).toList();
        if (scheduleChanges.isNotEmpty) {
          store.setKv('schedule_changes', jsonEncode(scheduleChanges));
        }
        store.setKv('schedule_data', jsonEncode(data));
        store.setKv('schedule_at', DateTime.now().toIso8601String());
        schedule = fresh;
        notifyListeners();
        return null;
      } catch (e) {
        error = 'Нет связи с сайтом расписания';
      }
    }
    return error;
  }

  /// Раз в день расписание обновляется само.
  Future<void> refreshScheduleIfStale() async {
    final at = scheduleFetched;
    if (at == null || DateTime.now().difference(at) > const Duration(hours: 12)) {
      await refreshSchedule();
    }
  }

  List<String> get pendingScheduleChanges {
    final raw = store.getKv('schedule_changes');
    if (raw == null) return const [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  void dismissScheduleChanges() {
    store.setKv('schedule_changes', null);
    notifyListeners();
  }
}
