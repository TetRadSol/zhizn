import 'dart:convert';

import '../data/models.dart';

/// Время пар на сайте расписания ФКМ.
const lessonTimes = {
  1: ('08:30', '09:50'),
  2: ('10:00', '11:20'),
  3: ('11:30', '12:50'),
  4: ('14:20', '15:40'),
  5: ('15:50', '17:10'),
  6: ('17:20', '18:40'),
};

/// Одна пара, разобранная из строки расписания.
class Lesson {
  Lesson({
    required this.date,
    required this.n,
    required this.raw,
    required this.subject,
    required this.start,
    required this.end,
    this.topic,
    this.type,
    this.teachers = const [],
    this.place,
  });

  final DateTime date;
  final int n;
  final String raw;
  final String subject;
  final String? topic;

  /// лекция, практика, семинар, зачёт, диф. зачёт, экзамен, коллоквиум
  final String? type;
  final List<String> teachers;
  final String? place;
  final String start;
  final String end;

  String get ref => '${ymd(date)}:$n';
  bool get isExam =>
      type == 'зачёт' || type == 'диф. зачёт' || type == 'экзамен';

  DateTime _at(String hm) {
    final p = hm.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(p[0]), int.parse(p[1]));
  }

  DateTime get startAt => _at(start);
  DateTime get endAt => _at(end);

  /// Место для плана дня: всё расписание — это ВУЗ.
  String get where => place ?? '';
}

final _timePrefix = RegExp(r'^(\d{1,2})[.:](\d{2})(?:\s*-\s*(\d{1,2})[.:](\d{2}))?\s*');
final _typeRe = RegExp(
  r'(?:^|\s)(Лекция|пр|с\*?|лаб|Диф\.?\s?[Зз]ач[её]т|[Зз]ач[её]т|Экзамен|коллоквиум|семинар)(?=\s|$)',
);
final _teacherRe = RegExp(r'[А-ЯЁ][а-яё]+(?:-[А-ЯЁ][а-яё]+)?\s[А-ЯЁ]\.\s?[А-ЯЁ]\.');
final _topicRe = RegExp(r'\s(т\.\s?[\d.,/\s-]+|\d+(?:[.,]\d+)*)$');

String _normType(String t) {
  final l = t.toLowerCase().replaceAll('*', '');
  if (l.startsWith('диф')) return 'диф. зачёт';
  if (l.startsWith('зач')) return 'зачёт';
  return switch (l) {
    'лекция' => 'лекция',
    'пр' => 'практика',
    'с' => 'семинар',
    'семинар' => 'семинар',
    'лаб' => 'лабораторная',
    'экзамен' => 'экзамен',
    'коллоквиум' => 'коллоквиум',
    _ => l,
  };
}

/// Разбирает строку пары: «ППФП т. 3.1 пр Ткачев В.С. Седнев С.М. спорт.городок».
Lesson parseLesson(DateTime date, int n, String raw) {
  var s = raw.trim();
  var (start, end) = lessonTimes[n] ?? ('08:30', '09:50');
  final tm = _timePrefix.firstMatch(s);
  if (tm != null) {
    start = '${tm[1]!.padLeft(2, '0')}:${tm[2]}';
    if (tm[3] != null) {
      end = '${tm[3]!.padLeft(2, '0')}:${tm[4]}';
    } else {
      final st = DateTime(2000, 1, 1, int.parse(tm[1]!), int.parse(tm[2]!))
          .add(const Duration(minutes: 80));
      end = '${st.hour.toString().padLeft(2, '0')}:${st.minute.toString().padLeft(2, '0')}';
    }
    s = s.substring(tm.end);
  }

  final teachers = _teacherRe.allMatches(s).map((m) => m[0]!).toList();
  final firstTeacher = _teacherRe.firstMatch(s);
  final head = firstTeacher == null ? s : s.substring(0, firstTeacher.start);

  String? type;
  var subjectPart = head.trim();
  final typeM = _typeRe.allMatches(head).lastOrNull;
  if (typeM != null) {
    type = _normType(typeM[1]!);
    subjectPart = head.substring(0, typeM.start).trim();
  }

  String? topic;
  final topM = _topicRe.firstMatch(subjectPart);
  if (topM != null && topM.start > 0) {
    topic = topM[1]!.trim();
    subjectPart = subjectPart.substring(0, topM.start).trim();
  }
  final ti = subjectPart.indexOf(' т.');
  if (ti > 0) {
    topic ??= subjectPart.substring(ti + 1).trim();
    subjectPart = subjectPart.substring(0, ti).trim();
  }

  String? place;
  if (firstTeacher != null) {
    var rest = s.substring(firstTeacher.start);
    for (final t in teachers) {
      rest = rest.replaceFirst(t, ' ');
    }
    rest = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
    place = rest.isEmpty ? null : rest;
  } else if (type == null) {
    // «День знаний А/з МАШ» — место не отделить надёжно, оставляем как есть
  }

  return Lesson(
    date: date,
    n: n,
    raw: raw,
    subject: subjectPart.replaceAll('*', '').trim(),
    topic: topic,
    type: type,
    teachers: teachers,
    place: place,
    start: start,
    end: end,
  );
}

/// Расписание одной группы.
class Schedule {
  Schedule(this.group, this.byDate);

  final String group;
  final Map<String, List<Lesson>> byDate;

  static Schedule empty(String group) => Schedule(group, {});

  /// Достаёт данные из страницы сайта: там лежит `const DATA = {...}`.
  static Map<String, dynamic> extractData(String html) {
    const marker = 'const DATA = ';
    final i = html.indexOf(marker);
    if (i < 0) throw const FormatException('На странице нет данных расписания');
    final start = i + marker.length;
    // Ищем конец JSON-объекта по балансу скобок с учётом строк.
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var j = start; j < html.length; j++) {
      final c = html[j];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == r'\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') inStr = true;
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          return jsonDecode(html.substring(start, j + 1)) as Map<String, dynamic>;
        }
      }
    }
    throw const FormatException('Данные расписания обрываются');
  }

  static Schedule fromData(Map<String, dynamic> data, String group) {
    final days = (data[group] as List?) ?? const [];
    final byDate = <String, List<Lesson>>{};
    for (final d in days) {
      final m = d as Map<String, dynamic>;
      final date = parseYmd(m['iso'] as String)!;
      final lessons = <Lesson>[];
      final ls = (m['lessons'] as Map).cast<String, dynamic>();
      for (final e in ls.entries) {
        final text = (e.value as String?)?.trim() ?? '';
        if (text.isEmpty) continue;
        lessons.add(parseLesson(date, int.parse(e.key), text));
      }
      lessons.sort((a, b) => a.n.compareTo(b.n));
      byDate[ymd(date)] = lessons;
    }
    return Schedule(group, byDate);
  }

  List<Lesson> on(DateTime d) => byDate[ymd(d)] ?? const [];

  Iterable<Lesson> get all sync* {
    final keys = byDate.keys.toList()..sort();
    for (final k in keys) {
      yield* byDate[k]!;
    }
  }

  Lesson? byRef(String ref) {
    final p = ref.split(':');
    for (final l in byDate[p[0]] ?? const <Lesson>[]) {
      if (l.n.toString() == p[1]) return l;
    }
    return null;
  }

  List<Lesson> exams(DateTime from) =>
      all.where((l) => l.isExam && !l.date.isBefore(dayOf(from))).toList();

  /// Ближайшая пара, название которой упомянуто в тексте.
  /// Если подходят несколько предметов, берётся совпавший длиннее всех.
  Lesson? nextLessonFor(List<String> tokens, DateTime now) {
    final best = <String>{};
    var bestLen = 0;
    for (final s in subjects) {
      final n = subjectMatchLength(tokens, s);
      if (n == 0 || n < bestLen) continue;
      if (n > bestLen) best.clear();
      bestLen = n;
      best.add(s);
    }
    if (best.isEmpty) return null;
    for (final l in all) {
      if (l.isExam || !l.startAt.isAfter(now)) continue;
      if (best.contains(l.subject)) return l;
    }
    return null;
  }

  /// Все разные названия предметов.
  Set<String> get subjects => all.map((l) => l.subject).toSet();

  /// Сравнение двух расписаний: какие дни поменялись.
  List<String> changedDays(Schedule other) {
    final out = <String>[];
    final keys = {...byDate.keys, ...other.byDate.keys};
    for (final k in keys) {
      final a = (byDate[k] ?? const []).map((l) => '${l.n}${l.raw}').join('|');
      final b = (other.byDate[k] ?? const []).map((l) => '${l.n}${l.raw}').join('|');
      if (a != b) out.add(k);
    }
    out.sort();
    return out;
  }
}

// ---------- Сопоставление текста с названием предмета ----------

const _stop = {'по', 'и', 'в', 'на', 'с', 'для', 'к', 'о', 'об', 'от'};

List<String> tokenize(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .split(RegExp(r'[^a-zа-я0-9]+'))
    .where((t) => t.isNotEmpty)
    .toList();

bool _tokEq(String u, String s) {
  if (u.length < 3 || s.length < 3) return u == s;
  var i = 0;
  while (i < u.length && i < s.length && u[i] == s[i]) {
    i++;
  }
  final shorter = u.length < s.length ? u.length : s.length;
  return i >= (shorter < 4 ? shorter : 4) && (i == shorter || i >= 5);
}

String acronym(String subject) {
  final words = subject
      .replaceAll('*', '')
      .split(RegExp(r'[\s-]+'))
      .where((w) => w.isNotEmpty && !_stop.contains(w.toLowerCase()) && !w.contains('.'))
      .toList();
  if (words.length < 2) return '';
  return words.map((w) => w[0]).join().toLowerCase().replaceAll('ё', 'е');
}

/// Сколько слов текста совпало с названием предмета (0 — не совпало).
/// «Суд. бухгалтерии» совпадает с «Судебная бухгалтерия», «ОРП» —
/// с «Оперативно-розыскная психология».
int subjectMatchLength(List<String> tokens, String subject) {
  final st = tokenize(subject);
  if (st.isEmpty) return 0;
  for (var i = 0; i + st.length <= tokens.length; i++) {
    var ok = true;
    for (var j = 0; j < st.length; j++) {
      if (!_tokEq(tokens[i + j], st[j])) {
        ok = false;
        break;
      }
    }
    if (ok) return st.length;
  }
  final ac = acronym(subject);
  if (ac.length >= 3 && tokens.contains(ac)) return 1;
  return 0;
}
