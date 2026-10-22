import '../data/models.dart';
import 'schedule.dart';

/// Настройки распорядка для плана дня.
class DayRules {
  const DayRules({
    this.wake = '06:30',
    this.sleep = '23:00',
    this.campusFrom = '08:00',
    this.campusTo = '16:00',
    this.campusDays = const [1, 2, 3, 4, 5, 6],
    this.road = 30,
    this.buffer = 10,
    this.reserve = 0.2,
  });

  final String wake;
  final String sleep;

  /// Когда в дни с парами вы в ВУЗе (телефон сдан).
  final String campusFrom;
  final String campusTo;
  final List<int> campusDays;

  /// Дорога до ВУЗа и обратно, минут.
  final int road;

  /// Перерыв между делами, минут.
  final int buffer;

  /// Какая доля свободного времени остаётся запасом на неожиданное.
  final double reserve;
}

class Slot {
  Slot(this.start, this.end, this.label, {this.task, this.lesson, this.fixed = false});
  final DateTime start;
  final DateTime end;
  final String label;
  final Task? task;
  final Lesson? lesson;
  final bool fixed;
  int get minutes => end.difference(start).inMinutes;
}

class DayPlan {
  DayPlan(this.day, this.slots, this.overflow, this.freeMinutes, this.busyReason);
  final DateTime day;

  /// Всё по порядку: пары, дела со временем и дела, поставленные в свободные окна.
  final List<Slot> slots;

  /// Обязательные дела (срок сегодня или раньше), которые не помещаются.
  final List<Task> overflow;
  final int freeMinutes;

  /// Если день занят форс-мажором — его название.
  final String? busyReason;

  int get plannedMinutes => slots.where((s) => s.task != null && !s.fixed).fold(0, (a, s) => a + s.minutes);
}

DateTime _at(DateTime day, String hm) {
  final p = hm.split(':');
  return DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
}

/// Сколько минут обычно занимает дело, если длительность не указана.
int defaultMinutes(Task t) => t.duration ?? switch (t.type) {
  'event' => 60,
  'hw' => 60,
  'shopping' || 'question' => 15,
  _ => 30,
};

/// Правило «как можно раньше»: дело ставится в ближайшее свободное окно, а не к сроку,
/// и в дне остаётся запас на неожиданное.
DayPlan planDay({
  required DateTime day,
  required DateTime now,
  required List<Task> tasks,
  required List<Lesson> lessons,
  List<({DateTime from, DateTime to, String title})> busy = const [],
  DayRules rules = const DayRules(),
}) {
  day = dayOf(day);
  final dayEnd = day.add(const Duration(days: 1));
  for (final b in busy) {
    if (!dayOf(b.from).isAfter(day) && !dayOf(b.to).isBefore(day)) {
      return DayPlan(day, const [], tasks.where((t) => !t.done && t.due != null && !t.due!.isAfter(day)).toList(), 0, b.title);
    }
  }

  // Занятое время
  final blocks = <(DateTime, DateTime)>[];
  void block(DateTime a, DateTime b) {
    if (b.isAfter(a)) blocks.add((a, b));
  }

  block(day, _at(day, rules.wake));
  final sleep = _at(day, rules.sleep);
  block(sleep.isAfter(_at(day, rules.wake)) ? sleep : dayEnd, dayEnd);
  if (dayOf(now) == day) block(day, now);
  if (lessons.isNotEmpty) {
    var from = lessons.first.startAt.subtract(Duration(minutes: rules.road));
    var to = lessons.map((l) => l.endAt).reduce((a, b) => a.isAfter(b) ? a : b).add(Duration(minutes: rules.road));
    if (rules.campusDays.contains(day.weekday)) {
      final cf = _at(day, rules.campusFrom), ct = _at(day, rules.campusTo);
      if (cf.isBefore(from)) from = cf;
      if (ct.isAfter(to)) to = ct;
    }
    block(from, to);
  }

  final slots = <Slot>[
    for (final l in lessons) Slot(l.startAt, l.endAt, '${l.n} пара · ${l.subject}', lesson: l, fixed: true),
  ];
  final open = tasks.where((t) => !t.done).toList();
  for (final t in open) {
    final at = t.at;
    if (at == null || dayOf(at) != day) continue;
    final end = at.add(Duration(minutes: defaultMinutes(t)));
    slots.add(Slot(at, end, t.title, task: t, fixed: true));
    block(at, end);
  }

  // Свободные окна
  blocks.sort((a, b) => a.$1.compareTo(b.$1));
  final windows = <(DateTime, DateTime)>[];
  var cursor = day;
  for (final (a, b) in blocks) {
    if (a.isAfter(cursor)) windows.add((cursor, a));
    if (b.isAfter(cursor)) cursor = b;
  }
  if (dayEnd.isAfter(cursor)) windows.add((cursor, dayEnd));
  final free = windows.fold(0, (a, w) => a + w.$2.difference(w.$1).inMinutes);
  var budget = (free * (1 - rules.reserve)).round();

  // Что ставить: сначала обязательное (просрочено и на сегодня), потом — «как можно раньше» — будущее
  final flexible = open.where((t) => t.time == null || t.due == null).where((t) => t.repeat == null || (t.due != null && !t.due!.isAfter(day))).toList();
  int rank(Task t) {
    final d = t.due;
    if (d != null && d.isBefore(day)) return 0;
    if (d != null && d == day) return 1;
    if (t.prio == Prio.red) return 2;
    if (d != null) return 3;
    return 4;
  }

  flexible.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final pa = Prio.rank(a.prio).compareTo(Prio.rank(b.prio));
    if (pa != 0) return pa;
    final da = a.due, db = b.due;
    if (da != null && db != null) return da.compareTo(db);
    return 0;
  });

  final overflow = <Task>[];
  final cursors = [for (final w in windows) w.$1];
  for (final t in flexible) {
    final need = defaultMinutes(t);
    final mandatory = rank(t) <= 1;
    if (!mandatory && (budget < need || (t.due != null && t.due!.isAfter(day.add(const Duration(days: 14)))))) continue;
    var placed = false;
    for (var i = 0; i < windows.length; i++) {
      final start = cursors[i];
      final end = start.add(Duration(minutes: need));
      if (!end.isAfter(windows[i].$2)) {
        slots.add(Slot(start, end, t.title, task: t));
        cursors[i] = end.add(Duration(minutes: rules.buffer));
        budget -= need;
        placed = true;
        break;
      }
    }
    if (!placed && mandatory) overflow.add(t);
  }

  slots.sort((a, b) => a.start.compareTo(b.start));
  return DayPlan(day, slots, overflow, free, null);
}
