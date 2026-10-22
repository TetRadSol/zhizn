import 'store.dart';

/// Виды записей в базе.
abstract final class Kinds {
  static const task = 'task';
  static const habit = 'habit';
  static const capture = 'capture';
  static const note = 'note';
  static const journal = 'journal';
  static const goal = 'goal';
  static const lesson = 'lesson'; // отметки к паре: посещаемость, заметки
  static const dict = 'dict'; // словарь сокращений
}

class Sphere {
  const Sphere(this.id, this.emoji, this.name);
  final String id;
  final String emoji;
  final String name;

  String get label => '$emoji $name';

  static const all = [
    Sphere('study', '🎓', 'Учёба'),
    Sphere('auto', '🚗', 'Автошкола'),
    Sphere('health', '💪', 'Здоровье и спорт'),
    Sphere('self', '📚', 'Саморазвитие'),
    Sphere('hobby', '🎨', 'Хобби'),
    Sphere('home', '🏡', 'Дом'),
  ];

  static Sphere? byId(String? id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Важность: красный, жёлтый, зелёный — как в Excel-трекере.
abstract final class Prio {
  static const red = 'r';
  static const yellow = 'y';
  static const green = 'g';
  static String emoji(String? p) =>
      switch (p) { 'r' => '🔴', 'y' => '🟡', 'g' => '🟢', _ => '' };
  static int rank(String? p) =>
      switch (p) { 'r' => 0, 'y' => 1, 'g' => 3, _ => 2 };
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseYmd(String? s) {
  if (s == null || s.isEmpty) return null;
  final p = s.split('-');
  if (p.length != 3) return null;
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

class Task {
  Task(this.e);
  final Entity e;

  String get id => e.id;
  String get title => (e['title'] as String?) ?? '';
  String get notes => (e['notes'] as String?) ?? '';
  String? get sphere => e['sphere'] as String?;
  DateTime? get due => parseYmd(e['due'] as String?);
  String? get time => e['time'] as String?;
  int? get duration => (e['dur'] as num?)?.toInt();
  String? get prio => e['prio'] as String?;
  Map<String, dynamic>? get repeat =>
      (e['repeat'] as Map?)?.cast<String, dynamic>();
  bool get done => e['done'] == true;
  DateTime? get doneAt =>
      e['doneAt'] == null ? null : DateTime.tryParse(e['doneAt'] as String);

  /// task — обычное дело, event — со временем, hw — ДЗ к паре,
  /// deadline — сдача, shopping — покупка, question — спросить кого-то.
  String get type => (e['type'] as String?) ?? 'task';
  bool get draft => e['draft'] == true;
  String? get lessonRef => e['lesson'] as String?;
  String? get captureId => e['capture'] as String?;
  int get doneCount => (e['doneCount'] as num?)?.toInt() ?? 0;

  /// Точный момент начала, если указано время.
  DateTime? get at {
    final d = due, t = time;
    if (d == null || t == null) return null;
    final p = t.split(':');
    return DateTime(d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1]));
  }

  bool completedOn(DateTime day) => e['c:${ymd(day)}'] == true;
}

class Habit {
  Habit(this.e);
  final Entity e;

  String get id => e.id;
  String get title => (e['title'] as String?) ?? '';
  String? get sphere => e['sphere'] as String?;

  /// Цель: в скольких процентах дней привычка выполнена.
  int get target => (e['target'] as num?)?.toInt() ?? 80;

  /// Дни недели (1 = понедельник). Пусто — каждый день.
  List<int> get days =>
      ((e['days'] as List?) ?? const []).map((x) => (x as num).toInt()).toList();
  int get order => (e['order'] as num?)?.toInt() ?? 0;

  bool activeOn(DateTime d) => days.isEmpty || days.contains(d.weekday);

  /// '✓' выполнено, '–' пропуск по уважительной, '✗' не выполнено, null — нет отметки.
  String? mark(DateTime d) => e['m:${ymd(d)}'] as String?;

  /// С какого дня привычка ведётся: дата создания или самая ранняя отметка.
  DateTime get since {
    var s = dayOf(DateTime.tryParse((e['created'] as String?) ?? '') ?? DateTime.now());
    for (final k in e.f.keys) {
      if (!k.startsWith('m:') || e.f[k] == null) continue;
      final d = parseYmd(k.substring(2));
      if (d != null && d.isBefore(s)) s = d;
    }
    return s;
  }

  /// Процент выполнения за последние [n] дней (дни до начала привычки не считаются).
  double percent(DateTime today, {int n = 30}) {
    var ok = 0, all = 0;
    final start = since;
    for (var i = 0; i < n; i++) {
      final d = today.subtract(Duration(days: i));
      if (d.isBefore(start)) break;
      if (!activeOn(d)) continue;
      final m = mark(d);
      if (m == '–') continue;
      if (m == null && i == 0) continue; // сегодня ещё не вечер
      all++;
      if (m == '✓') ok++;
    }
    return all == 0 ? 0 : ok / all;
  }

  /// Серия: сколько дней подряд выполнено. Пропуск «–» серию не обрывает.
  int streak(DateTime today) {
    var s = 0;
    for (var i = 0; i < 400; i++) {
      final d = today.subtract(Duration(days: i));
      if (!activeOn(d)) continue;
      final m = mark(d);
      if (m == '✓') {
        s++;
      } else if (m == '–' || (m == null && i == 0)) {
        continue;
      } else {
        break;
      }
    }
    return s;
  }
}

class Capture {
  Capture(this.e);
  final Entity e;

  String get id => e.id;
  String get text => (e['text'] as String?) ?? '';
  DateTime get created =>
      DateTime.tryParse((e['created'] as String?) ?? '') ?? DateTime(2000);
  List<String> get results =>
      ((e['results'] as List?) ?? const []).cast<String>();
  List<Map<String, dynamic>> get files => ((e['files'] as List?) ?? const [])
      .map((x) => (x as Map).cast<String, dynamic>())
      .toList();

  /// rules — разобрано правилами, jarvis — проверено Джарвисом.
  String get status => (e['status'] as String?) ?? 'rules';
}
