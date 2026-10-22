import '../data/models.dart';
import 'recurrence.dart';
import 'schedule.dart';

/// Результат разбора одной строки записи.
class Parsed {
  Parsed(this.kind, this.title);

  /// task, habit, goal, note, journal
  String kind;
  String title;

  /// Для задач: task, event, hw, deadline, shopping, question.
  /// Для заметок: idea, thought, place, note. Для журнала: money, workout, weight, mood.
  String type = 'task';
  DateTime? due;
  String? time;
  int? duration;
  String? prio;
  String? sphere;
  Map<String, dynamic>? repeat;
  String? lessonRef;
  double? amount;

  /// Что и почему поняли правила — показывается в ленте записей.
  final List<String> why = [];

  Map<String, dynamic> toTaskFields() => {
    'title': title,
    'type': type,
    if (due != null) 'due': ymd(due!),
    if (time != null) 'time': time,
    if (duration != null) 'dur': duration,
    if (prio != null) 'prio': prio,
    if (sphere != null) 'sphere': sphere,
    if (repeat != null) 'repeat': repeat,
    if (lessonRef != null) 'lesson': lessonRef,
  };
}

/// Разбор записей правилами: сразу и без интернета.
class Parser {
  Parser({required this.now, Schedule? schedule, Map<String, String>? dict})
    : schedule = schedule ?? Schedule.empty(''),
      dict = dict ?? const {};

  final DateTime now;
  final Schedule schedule;

  /// Обработчик совпадения ставит true, если совпадение не подошло
  /// и текст вырезать не нужно.
  bool _reject = false;

  /// Ваши сокращения: «спортмасс» → id сферы.
  final Map<String, String> dict;

  DateTime get today => dayOf(now);

  List<Parsed> parse(String text) => splitItems(text).map(parseOne).toList();

  /// Делит запись на отдельные дела: по строкам, «;» и пунктам списка.
  static List<String> splitItems(String text) {
    final out = <String>[];
    for (var line in text.split(RegExp(r'[\r\n;]+'))) {
      line = line.replaceFirst(RegExp(r'^\s*(?:[-–—•*·▪✓☐]|\d{1,2}[.)])\s+'), '').trim();
      if (line.isNotEmpty) out.add(line);
    }
    return out;
  }

  Parsed parseOne(String line) {
    var s = ' ${line.trim()} ';
    final p = Parsed('task', line.trim());

    String cut(RegExp re, void Function(RegExpMatch m) on) {
      final m = re.firstMatch(s);
      if (m != null) {
        _reject = false;
        on(m);
        if (!_reject) s = '${s.substring(0, m.start)} ${s.substring(m.end)}';
        _reject = false;
      }
      return s;
    }

    // --- Виды записей по первому слову ---
    final low = line.toLowerCase().trim();
    final notePrefix = RegExp(r'^(идея|мысль|заметка|запомнить|конспект|адрес|место)\s*[:\-–—]?\s+');
    final nm = notePrefix.firstMatch(low);
    if (nm != null) {
      p.kind = 'note';
      p.type = switch (nm[1]) {
        'идея' => 'idea',
        'мысль' => 'thought',
        'адрес' || 'место' => 'place',
        _ => 'note',
      };
      p.title = _cap(line.trim().substring(nm.end));
      p.why.add('заметка');
      p.sphere = _sphereOf(tokenize(p.title));
      return p;
    }
    final hm = RegExp(r'^привычка\s*[:\-–—]?\s+').firstMatch(low);
    if (hm != null) {
      p.kind = 'habit';
      p.title = _cap(line.trim().substring(hm.end));
      p.sphere = _sphereOf(tokenize(p.title));
      p.why.add('привычка');
      return p;
    }
    final journal = _journal(line.trim());
    if (journal != null) return journal;

    // --- Важность ---
    cut(RegExp(r'🔴|‼️|!!+'), (_) => p.prio = Prio.red);
    cut(RegExp(r'🟡'), (_) => p.prio = Prio.yellow);
    cut(RegExp(r'🟢'), (_) => p.prio = Prio.green);
    cut(RegExp(r'\s(срочно|очень важно|важно)(?![а-яёА-ЯЁ\w])[!,.]?', caseSensitive: false), (_) => p.prio = Prio.red);

    // --- Повторы ---
    _repeat(p, cut);

    // --- Время ---
    cut(
      RegExp(r'\s(?:с)\s(\d{1,2})(?:[:.](\d{2}))?\s(?:до|по|-)\s(\d{1,2})(?:[:.](\d{2}))?(?=[\s,.]|$)'),
      (m) {
        final a = int.parse(m[1]!) * 60 + int.parse(m[2] ?? '0');
        final b = int.parse(m[3]!) * 60 + int.parse(m[4] ?? '0');
        if (a < 24 * 60 && b > a && b <= 24 * 60) {
          p.time = _hm(a);
          p.duration = b - a;
        } else {
          _reject = true;
        }
      },
    );
    if (p.time == null) {
      cut(RegExp(r'\s(?:(в|к|до|на)\s)?(\d{1,2}):([0-5]\d)(?=[\s,.]|$)'), (m) {
        final h = int.parse(m[2]!);
        if (h > 23) {
          _reject = true;
          return;
        }
        p.time = _hm(h * 60 + int.parse(m[3]!));
      });
    }
    if (p.time == null) {
      cut(RegExp(r'\s(в|к|до)\s(\d{1,2})\.([0-5]\d)(?=[\s,]|$)'), (m) {
        final h = int.parse(m[2]!), mm = int.parse(m[3]!);
        // «к 15.00» — время; «до 10.10» с месяцем 1–12 — скорее дата
        if (h < 24 && (m[1] == 'в' || mm > 12 || mm == 0)) {
          p.time = _hm(h * 60 + mm);
        } else {
          _reject = true;
        }
      });
    }
    if (p.time == null) {
      cut(
        RegExp(r'\s(?:в|к)\s(\d{1,2})\s?(?:(час(?:а|ов)?|ч)(?![а-яёА-ЯЁ\w]))?\s?(утра|вечера|дня|ночи)?(?=[\s,.]|$)'),
        (m) {
          var h = int.parse(m[1]!);
          if ((m[2] == null && m[3] == null) || h > 23) {
            _reject = true;
            return;
          }
          if ((m[3] == 'вечера' || m[3] == 'дня') && h < 12) h += 12;
          p.time = _hm(h * 60);
        },
      );
    }

    // --- Длительность ---
    cut(RegExp(r'\s(?:на\s)?(\d+(?:[.,]\d+)?)\s?(мин(?:ут[ауы]?)?|ч(?:ас(?:а|ов)?)?)(?![а-яёА-ЯЁ\w])\.?', caseSensitive: false), (m) {
      final v = double.parse(m[1]!.replaceAll(',', '.'));
      p.duration = m[2]!.startsWith('м') ? v.round() : (v * 60).round();
    });
    cut(RegExp(r'\s(?:на\s)?полчаса(?![а-яёА-ЯЁ\w])'), (_) => p.duration = 30);
    cut(RegExp(r'\s(?:на\s)?полтора часа(?![а-яёА-ЯЁ\w])'), (_) => p.duration = 90);

    // --- Дата ---
    _date(p, cut);

    // --- Чистим название ---
    var title = s
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s([,.!?])'), r'$1')
        .trim();
    title = title.replaceAll(RegExp(r'^(?:[,.\-–—:]\s*)+|(?:\s*[,\-–—:])+$'), '').trim();
    title = title.replaceAll(RegExp(r'\s(в|к|до|на|по|с|во|ко)$', caseSensitive: false), '').trim();
    title = title.replaceAll(RegExp(r'^(в|к|до|на|с|во|ко)\s', caseSensitive: false), '').trim();
    p.title = _cap(title.isEmpty ? line.trim() : title);

    _classify(p);
    return p;
  }

  // ---------- Даты ----------

  static const _months = {
    'январ': 1, 'феврал': 2, 'март': 3, 'апрел': 4, 'ма': 5, 'июн': 6,
    'июл': 7, 'август': 8, 'сентябр': 9, 'октябр': 10, 'ноябр': 11, 'декабр': 12,
  };
  static const _wdays = {
    'понедельник': 1, 'вторник': 2, 'сред': 3, 'четверг': 4,
    'пятниц': 5, 'суббот': 6, 'воскресень': 7,
  };
  static const _wdShort = {'пн': 1, 'вт': 2, 'ср': 3, 'чт': 4, 'пт': 5, 'сб': 6, 'вс': 7};
  static const _nums = {
    'один': 1, 'одну': 1, 'два': 2, 'две': 2, 'три': 3, 'четыре': 4, 'пять': 5,
    'шесть': 6, 'семь': 7, 'восемь': 8, 'девять': 9, 'десять': 10,
  };

  void _date(Parsed p, String Function(RegExp, void Function(RegExpMatch)) cut) {
    final t = today;
    void set(DateTime d, {bool deadline = false}) {
      p.due ??= d;
      if (deadline && p.type == 'task') p.type = 'deadline';
    }

    cut(RegExp(r'\s(сегодня|сейчас)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) => set(t));
    cut(RegExp(r'\s(послезавтра)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) => set(t.add(const Duration(days: 2))));
    cut(RegExp(r'\s(завтра)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) => set(t.add(const Duration(days: 1))));

    // через 3 дня / через неделю / через два месяца
    cut(
      RegExp(r'\sчерез\s(\d+|[а-я]+\s)?\s?(дн(?:я|ей)|день|недел(?:ю|и|ь)|месяц(?:а|ев)?)(?![а-яёА-ЯЁ\w])', caseSensitive: false),
      (m) {
        final w = m[1]?.trim();
        final n = w == null ? 1 : (int.tryParse(w) ?? _nums[w] ?? 1);
        final u = m[2]!;
        if (u.startsWith('д')) set(t.add(Duration(days: n)));
        if (u.startsWith('н')) set(t.add(Duration(days: 7 * n)));
        if (u.startsWith('м')) set(DateTime(t.year, t.month + n, t.day));
      },
    );

    // 25 октября / к 3 ноября
    cut(
      RegExp(r'\s(?:(к|до|на)\s)?(\d{1,2})\s(январ|феврал|март|апрел|ма|июн|июл|август|сентябр|октябр|ноябр|декабр)[а-я]*(?![а-яёА-ЯЁ\w])', caseSensitive: false),
      (m) {
        final mon = _months[m[3]!.toLowerCase()]!;
        var d = DateTime(t.year, mon, int.parse(m[2]!));
        if (d.isBefore(t.subtract(const Duration(days: 31)))) d = DateTime(t.year + 1, mon, d.day);
        set(d, deadline: m[1] == 'до' || m[1] == 'к');
      },
    );

    // 25.10 / 25.10.2026 / до 25.10
    cut(
      RegExp(r'\s(?:(к|до|на)\s)?(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?(?=[\s,]|$)'),
      (m) {
        final day = int.parse(m[2]!), mon = int.parse(m[3]!);
        if (mon < 1 || mon > 12 || day < 1 || day > 31) return;
        var y = m[4] == null ? t.year : int.parse(m[4]!);
        if (y < 100) y += 2000;
        var d = DateTime(y, mon, day);
        if (m[4] == null && d.isBefore(t.subtract(const Duration(days: 31)))) d = DateTime(y + 1, mon, day);
        set(d, deadline: m[1] == 'до' || m[1] == 'к');
      },
    );

    // в пятницу / к понедельнику / до среды / пт
    cut(
      RegExp(r'\s(?:(в|во|к|ко|до|на)\s)?(понедельник|вторник|сред|четверг|пятниц|суббот|воскресень)[а-я]*(?![а-яёА-ЯЁ\w])', caseSensitive: false),
      (m) {
        final wd = _wdays[m[2]!.toLowerCase()]!;
        set(_nextWeekday(wd), deadline: m[1] == 'до' || m[1] == 'к' || m[1] == 'ко');
      },
    );
    cut(RegExp(r'\s(?:(в|во|к|до)\s)?(пн|вт|ср|чт|пт|сб|вс)(?![а-яёА-ЯЁ\w])\.?', caseSensitive: false), (m) {
      set(_nextWeekday(_wdShort[m[2]!.toLowerCase()]!));
    });

    cut(RegExp(r'\sна\sследующей\sнеделе(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) {
      set(t.add(Duration(days: 8 - t.weekday)));
    });
    cut(RegExp(r'\sна\sэтой\sнеделе(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) {
      set(t.add(Duration(days: 7 - t.weekday)));
    });
    cut(RegExp(r'\sна\sвыходных(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) {
      set(t.weekday >= 6 ? t : t.add(Duration(days: 6 - t.weekday)));
    });
  }

  DateTime _nextWeekday(int wd) {
    var d = today.add(const Duration(days: 1));
    while (d.weekday != wd) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  // ---------- Повторы ----------

  void _repeat(Parsed p, String Function(RegExp, void Function(RegExpMatch)) cut) {
    cut(RegExp(r'\s(каждый\sдень|ежедневно|каждое\sутро|каждый\sвечер)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) {
      p.repeat = Repeat.daily();
    });
    cut(RegExp(r'\s(?:каждые|раз\sв)\s(\d+|[а-я]+)\s(дн(?:я|ей)|день|недел[иья])(?![а-яёА-ЯЁ\w])', caseSensitive: false), (m) {
      final n = int.tryParse(m[1]!) ?? _nums[m[1]!.toLowerCase()] ?? 1;
      p.repeat = Repeat.daily(m[2]!.startsWith('н') ? n * 7 : n);
    });
    cut(RegExp(r'\sчерез\s(\d+)\s(?:дн(?:я|ей)|день)\sпосле\sвыполнения(?![а-яёА-ЯЁ\w])', caseSensitive: false), (m) {
      p.repeat = Repeat.afterDone(int.parse(m[1]!));
    });
    cut(RegExp(r'\s(по\sбудням)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) => p.repeat = Repeat.weekly([1, 2, 3, 4, 5]));
    cut(RegExp(r'\s(по\sвыходным)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) => p.repeat = Repeat.weekly([6, 7]));
    // каждый понедельник / по понедельникам и средам / каждую среду и пятницу
    cut(
      RegExp(
        r'\s(?:кажд[а-я]*|по)\s((?:(?:понедельник|вторник|сред|четверг|пятниц|суббот|воскресень)[а-я]*(?:\s*,\s*|\sи\s)?)+)',
        caseSensitive: false,
      ),
      (m) {
        final days = <int>[];
        for (final w in RegExp(r'(понедельник|вторник|сред|четверг|пятниц|суббот|воскресень)', caseSensitive: false)
            .allMatches(m[1]!)) {
          days.add(_wdays[w[1]!.toLowerCase()]!);
        }
        p.repeat = Repeat.weekly(days);
        p.due ??= _nextWeekdayIncl(days);
      },
    );
    cut(RegExp(r'\s(каждую\sнеделю|еженедельно|раз\sв\sнеделю)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) {
      p.repeat = Repeat.weekly([today.weekday]);
    });
    cut(RegExp(r'\sкаждое\s(\d{1,2})(?:-?е)?\sчисло(?![а-яёА-ЯЁ\w])', caseSensitive: false), (m) {
      final md = int.parse(m[1]!);
      p.repeat = Repeat.monthly(md);
      var d = DateTime(today.year, today.month, md);
      if (d.isBefore(today)) d = DateTime(today.year, today.month + 1, md);
      p.due ??= d;
    });
    cut(RegExp(r'\s(каждый\sмесяц|ежемесячно|раз\sв\sмесяц)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) {
      p.repeat = Repeat.monthly(today.day);
    });
    cut(RegExp(r'\s(каждый\sгод|ежегодно|раз\sв\sгод)(?![а-яёА-ЯЁ\w])', caseSensitive: false), (_) {
      p.repeat = Repeat.yearly();
    });
    if (p.repeat != null) {
      cut(RegExp(r'\s(\d+)\sраз(?:а)?(?![а-яёА-ЯЁ\w])(?!\sв)', caseSensitive: false), (m) {
        p.repeat = {...p.repeat!, 'count': int.parse(m[1]!)};
      });
      cut(RegExp(r'\sдо\s(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?(?=[\s,]|$)'), (m) {
        var y = m[3] == null ? today.year : int.parse(m[3]!);
        if (y < 100) y += 2000;
        var d = DateTime(y, int.parse(m[2]!), int.parse(m[1]!));
        if (m[3] == null && d.isBefore(today)) d = DateTime(y + 1, d.month, d.day);
        p.repeat = {...p.repeat!, 'until': ymd(d)};
      });
      p.due ??= today;
    }
  }

  DateTime _nextWeekdayIncl(List<int> days) {
    var d = today;
    for (var i = 0; i < 7; i++) {
      if (days.contains(d.weekday)) return d;
      d = d.add(const Duration(days: 1));
    }
    return today;
  }

  // ---------- Журнал: «обед 7,5», «жим 60 на 10», «вес 72,5» ----------

  static const _spend = {
    'обед', 'ужин', 'завтрак', 'кофе', 'такси', 'продукты', 'проезд', 'бензин',
    'кафе', 'магазин', 'связь', 'интернет', 'подписка', 'одежда', 'аптека',
    'шаурма', 'перекус', 'еда', 'автобус', 'метро',
  };

  Parsed? _journal(String line) {
    final l = line.toLowerCase();
    var m = RegExp(r'^вес\s*[:\-]?\s*(\d{2,3}(?:[.,]\d+)?)\s*(кг)?$').firstMatch(l);
    if (m != null) {
      return Parsed('journal', line)
        ..type = 'weight'
        ..amount = double.parse(m[1]!.replaceAll(',', '.'))
        ..sphere = 'health'
        ..why.add('вес');
    }
    m = RegExp(r'^настроение\s*[:\-]?\s*(\d{1,2})').firstMatch(l);
    if (m != null) {
      return Parsed('journal', line)
        ..type = 'mood'
        ..amount = double.parse(m[1]!)
        ..why.add('настроение');
    }
    if (RegExp(r'^(жим|присед|тяга|подтяг|отжим|выпады|бицепс|трицепс|становая)[а-я]*\s.*\d+\s*(на|x|х|×)\s*\d+').hasMatch(l)) {
      return Parsed('journal', line)
        ..type = 'workout'
        ..sphere = 'health'
        ..why.add('тренировка');
    }
    m = RegExp(r'^([а-яё ]{2,30}?)\s+(\d+(?:[.,]\d{1,2})?)\s*(br|byn|руб\.?|р\.?|\$|usd|долл\.?)?$').firstMatch(l);
    if (m != null) {
      final words = m[1]!.trim().split(' ');
      final isSpend = _spend.contains(words.first) ||
          RegExp(r'^(потратил|расход|доход|получил|зарплата|стипендия)').hasMatch(m[1]!);
      if (isSpend || m[3] != null) {
        return Parsed('journal', line)
          ..type = 'money'
          ..amount = double.parse(m[2]!.replaceAll(',', '.'))
          ..why.add(m[3] == r'$' || m[3] == 'usd' || (m[3]?.startsWith('долл') ?? false) ? 'трата, \$' : 'трата, Br');
      }
    }
    return null;
  }

  // ---------- Вид, сфера, ДЗ к паре ----------

  static const _sphereWords = <String, List<String>>{
    'study': [
      'дз', 'домашк', 'практикум', 'реферат', 'доклад', 'курсов', 'диплом', 'зачет',
      'экзамен', 'семинар', 'лекци', 'конспект', 'тсп', 'ппфп', 'сесси', 'учеб',
      'коллоквиум', 'пара', 'пары', 'вуз', 'кафедр', 'методичк', 'норматив',
    ],
    'auto': ['автозачет', 'вождени', 'пдд', 'автошкол', 'билет', 'инструктор', 'права', 'площадк'],
    'health': [
      'трениров', 'зал', 'жим', 'бег', 'пробежк', 'присед', 'отжим', 'подтяг', 'пресс',
      'протеин', 'креатин', 'витамин', 'омега', 'магни', 'врач', 'стоматолог', 'растяжк',
      'зарядк', 'спортмасс', 'кача', 'вес', 'спорт',
    ],
    'self': [
      'книг', 'читать', 'прочитать', 'английск', 'скороговор', 'риторик', 'substack',
      'каллиграф', 'калиграф', 'почерк', 'подкаст', 'статью', 'стать', 'курс',
    ],
    'hobby': ['рисова', 'гитар', 'музык', 'хобби', 'фотограф', 'рисунок'],
    'home': [
      'постира', 'стирк', 'убра', 'уборк', 'помыть', 'мыть', 'пропылесос', 'пылесос',
      'приготов', 'купить', 'продукт', 'посуд', 'погладить', 'гладить', 'мусор',
      'комнат', 'постельн', 'белье', 'ремонт', 'оплатить',
    ],
  };

  String? _sphereOf(List<String> tokens) {
    for (final t in tokens) {
      final d = dict[t];
      if (d != null && Sphere.byId(d) != null) return d;
    }
    for (final e in _sphereWords.entries) {
      for (final t in tokens) {
        for (final w in e.value) {
          if (w.length <= 4 ? t == w || (w.length == 4 && t.startsWith(w)) : t.startsWith(w)) {
            if (e.key == 'self' && w == 'курс' && t.startsWith('курсов')) continue;
            return e.key;
          }
        }
      }
    }
    return null;
  }

  void _classify(Parsed p) {
    final tokens = tokenize(p.title);
    final l = p.title.toLowerCase();

    if (RegExp(r'^(цель|проект)\s*[:\-–—]?\s+').hasMatch(l) ||
        RegExp(r'^(диплом|дипломная работа|курсовая|курсовая работа|курсовой проект)$').hasMatch(l)) {
      p.kind = 'goal';
      p.title = _cap(p.title.replaceFirst(RegExp(r'^(цель|проект)\s*[:\-–—]?\s+', caseSensitive: false), ''));
      p.sphere = _sphereOf(tokens) ?? 'study';
      p.why.add('цель с этапами');
      return;
    }

    if (l.startsWith('купить ')) {
      p.type = 'shopping';
    } else if (RegExp(r'^(спросить|узнать у|уточнить у|написать|позвонить)(?![а-яёА-ЯЁ\w])').hasMatch(l)) {
      p.type = 'question';
    } else if (RegExp(r'(?<![а-яёА-ЯЁ\w])(сдать|сдача|дедлайн|зачет|зачёт|экзамен)').hasMatch(l) && p.due != null) {
      p.type = 'deadline';
    }
    if (p.time != null &&
        (p.duration != null ||
            RegExp(r'(?<![а-яёА-ЯЁ\w])(встреча|созвон|вождени|наряд|при[её]м|врач|занятие|кино|тренировк|экзамен|зач[её]т)').hasMatch(l))) {
      if (p.type == 'task') p.type = 'event';
    }

    p.sphere = _sphereOf(tokens);

    // ДЗ к ближайшей паре по предмету из расписания
    final lesson = schedule.nextLessonFor(tokens, now);
    if (lesson != null) {
      p.sphere = 'study';
      p.lessonRef = lesson.ref;
      if (p.type == 'task') p.type = 'hw';
      if (p.due == null) {
        final eve = lesson.date.subtract(const Duration(days: 1));
        p.due = eve.isBefore(today) ? today : eve;
        p.why.add('ДЗ к паре ${_dm(lesson.date)}, срок накануне');
      } else {
        p.why.add('к паре «${lesson.subject}»');
      }
    }

    if (p.sphere != null) p.why.insert(0, Sphere.byId(p.sphere)!.label);
    if (p.repeat != null) p.why.add(Repeat.describe(p.repeat));
  }

  static String _dm(DateTime d) => '${d.day}.${d.month.toString().padLeft(2, '0')}';
  static String _hm(int min) =>
      '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';
  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
