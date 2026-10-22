import 'dart:math';

import '../data/models.dart';
import '../data/store.dart';
import 'finance.dart';

/// Опыт, уровни, идеальные дни, награды и единая шкала — как в Excel-трекере, только считается само.
class Motivation {
  Motivation(this.store, this.today);
  final Store store;
  final DateTime today;

  late final List<Habit> habits = store.ofKind(Kinds.habit).map(Habit.new).toList();
  late final List<Task> tasks = store.ofKind(Kinds.task).map(Task.new).toList();

  /// Идеальный день: все привычки этого дня отмечены ✓ или –, и хотя бы одна ✓.
  bool ideal(DateTime d) {
    final active = habits.where((h) => h.activeOn(d) && !h.since.isAfter(d)).toList();
    if (active.isEmpty) return false;
    var any = false;
    for (final h in active) {
      final m = h.mark(d);
      if (m == '✓') {
        any = true;
      } else if (m != '–') {
        return false;
      }
    }
    return any;
  }

  DateTime get start {
    var s = today;
    for (final h in habits) {
      if (h.since.isBefore(s)) s = h.since;
    }
    for (final t in tasks) {
      final c = DateTime.tryParse((t.e['created'] as String?) ?? '');
      if (c != null && dayOf(c).isBefore(s)) s = dayOf(c);
    }
    return s;
  }

  Iterable<DateTime> get days sync* {
    for (var d = start; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      yield d;
    }
  }

  int get idealDays => days.where(ideal).length;

  int get totalChecks => habits.fold(0, (a, h) => a + h.e.f.entries.where((e) => e.key.startsWith('m:') && e.value == '✓').length);

  int get tasksDone => tasks.fold(0, (a, t) => a + t.e.f.entries.where((e) => e.key.startsWith('c:') && e.value == true).length + (t.done ? 1 : 0));

  /// Лучшая серия среди всех привычек.
  int get bestStreak {
    var best = 0;
    for (final h in habits) {
      var cur = 0;
      for (final d in days) {
        if (!h.activeOn(d)) continue;
        final m = h.mark(d);
        if (m == '✓') {
          cur++;
          best = max(best, cur);
        } else if (m != '–') {
          cur = 0;
        }
      }
    }
    return best;
  }

  /// Средний процент привычек за период (как «Итог» в Excel).
  double get habitsPercent {
    if (habits.isEmpty) return 0;
    final n = days.length.clamp(1, 365);
    return habits.map((h) => h.percent(today, n: n)).fold(0.0, (a, b) => a + b) / habits.length;
  }

  int get examsPassed => store.ofKind(Kinds.lesson).where((e) => e['passed'] == true).length;

  int get trainMinutes => store.ofKind(Kinds.metrics).fold(0, (a, e) => a + ((e['train'] as num?)?.toInt() ?? 0));

  double get studyHours => store.ofKind(Kinds.metrics).fold(0.0, (a, e) => a + ((e['study'] as num?)?.toDouble() ?? 0));

  /// Опыт: дело +10 (🔴 +20), привычка ✓ +5, пара ✓ +3, идеальный день +30, недельный обзор +20.
  int get xp {
    var x = 0;
    for (final t in tasks) {
      final n = t.e.f.entries.where((e) => e.key.startsWith('c:') && e.value == true).length + (t.done ? 1 : 0);
      x += n * (t.prio == Prio.red ? 20 : 10);
    }
    x += totalChecks * 5;
    x += store.ofKind(Kinds.lesson).where((e) => e['att'] == '✓').length * 3;
    x += idealDays * 30;
    x += store.ofKind(Kinds.week).where((e) => e['score'] != null).length * 20;
    return x;
  }

  static const levelNames = ['Новичок', 'Ученик', 'Практик', 'Боец', 'Мастер', 'Чемпион', 'Легенда'];

  /// Уровень n начинается с 100·n·(n−1)/2 опыта: 0, 100, 300, 600, 1000…
  static int levelOf(int xp) => ((1 + sqrt(1 + 8 * xp / 100)) / 2).floor();
  static int xpFor(int level) => 100 * level * (level - 1) ~/ 2;

  ({int level, String name, int xp, int from, int to}) get level {
    final x = xp, l = levelOf(x);
    return (level: l, name: levelNames[min(l - 1, levelNames.length - 1)], xp: x, from: xpFor(l), to: xpFor(l + 1));
  }

  /// Значение условия награды.
  num value(String cond) => switch (cond) {
    'streak' => bestStreak,
    'ideal' => idealDays,
    'checks' => totalChecks,
    'percent' => (habitsPercent * 100).round(),
    'savings' => totalSaved(store),
    'tasks' => tasksDone,
    'train' => trainMinutes,
    'exams' => examsPassed,
    'level' => level.level,
    _ => 0,
  };

  static const conditions = {
    'streak': 'Рекорд серии 🔥, дней',
    'ideal': 'Идеальных дней ⭐',
    'checks': 'Всего отметок ✓',
    'percent': 'Итог привычек, %',
    'savings': 'Накоплено, Br',
    'tasks': 'Сделано дел',
    'train': 'Минут тренировок',
    'exams': 'Сдано зачётов/экзаменов',
    'level': 'Уровень',
  };

  /// Прогресс цели 0..1 и текущее значение.
  ({double progress, num? current}) goal(Entity g) {
    final stages = ((g['stages'] as List?) ?? const []).whereType<Map>().toList();
    num? cur = switch (g['source']) {
      'savings' => totalSaved(store),
      'exams' => examsPassed,
      'study_hours' => studyHours,
      'driving' => tasks.where((t) => t.title.toLowerCase().contains('вожден')).fold<int>(0, (a, t) => a + t.e.f.entries.where((e) => e.key.startsWith('c:') && e.value == true).length + (t.done ? 1 : 0)),
      'weight' => latestWeight(store),
      _ => g['current'] as num?,
    };
    final target = num.tryParse('${g['target'] ?? ''}'.replaceAll(',', '.'));
    final startV = num.tryParse('${g['start'] ?? ''}'.replaceAll(',', '.')) ?? (g['source'] == 'weight' ? null : 0);
    if (cur != null && target != null && startV != null && target != startV) {
      return (progress: ((cur - startV) / (target - startV)).clamp(0, 1).toDouble(), current: cur);
    }
    if (stages.isNotEmpty) {
      return (progress: stages.where((s) => s['d'] == true).length / stages.length, current: cur);
    }
    return (progress: 0, current: cur);
  }

  /// Единая шкала: среднее из привычек, дел за неделю, посещаемости пар и целей.
  ({double total, double habits, double? tasks, double? lessons, double? goals}) get scale {
    final h = habits.isEmpty ? 0.0 : habits.map((x) => x.percent(today)).fold(0.0, (a, b) => a + b) / habits.length;
    final weekAgo = today.subtract(const Duration(days: 7));
    var due = 0, done = 0;
    for (final t in tasks) {
      final d = t.due;
      if (d != null && d.isAfter(weekAgo) && !d.isAfter(today)) due++;
      if (t.done && t.doneAt != null && t.doneAt!.isAfter(weekAgo)) done++;
    }
    final tp = (due + done) == 0 ? null : done / (due + done);
    final marks = store.ofKind(Kinds.lesson).map((e) => e['att']).where((m) => m == '✓' || m == '✗').toList();
    final lp = marks.isEmpty ? null : marks.where((m) => m == '✓').length / marks.length;
    final goals = store.ofKind(Kinds.goal).toList();
    final gp = goals.isEmpty ? null : goals.map((g) => goal(g).progress).fold(0.0, (a, b) => a + b) / goals.length;
    final parts = [h, ?tp, ?lp, ?gp];
    return (total: parts.fold(0.0, (a, b) => a + b) / parts.length, habits: h, tasks: tp, lessons: lp, goals: gp);
  }
}

double? latestWeight(Store s) {
  final b = s.ofKind(Kinds.body).where((e) => e['weight'] != null).toList()
    ..sort((a, b) => ((b['date'] as String?) ?? '').compareTo((a['date'] as String?) ?? ''));
  return b.isEmpty ? null : (b.first['weight'] as num).toDouble();
}

/// Шкала из блоков: ████████░░
String blocks(double v, [int n = 10]) {
  final f = (v.clamp(0, 1) * n).round();
  return '${'█' * f}${'░' * (n - f)}';
}
