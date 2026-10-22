import '../data/models.dart';

/// Повтор задачи хранится как словарь:
/// t: d — каждые n дней, w — по дням недели (days), a — через n дней после
/// выполнения, m — каждое md-е число месяца, y — раз в год;
/// until — до даты, count — сколько раз всего.
class Repeat {
  static Map<String, dynamic> daily([int n = 1]) => {'t': 'd', 'n': n};
  static Map<String, dynamic> weekly(List<int> days) => {'t': 'w', 'days': days};
  static Map<String, dynamic> afterDone(int n) => {'t': 'a', 'n': n};
  static Map<String, dynamic> monthly(int day) => {'t': 'm', 'md': day};
  static Map<String, dynamic> yearly() => {'t': 'y'};

  static const _wd = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

  /// Понятное описание: «по пн, ср», «каждые 3 дня».
  static String describe(Map<String, dynamic>? r) {
    if (r == null) return 'не повторять';
    final n = (r['n'] as num?)?.toInt() ?? 1;
    var s = switch (r['t']) {
      'd' when n == 1 => 'каждый день',
      'd' => 'каждые $n ${_days(n)}',
      'w' => _weekly(r),
      'a' => 'через $n ${_days(n)} после выполнения',
      'm' => 'каждое ${r['md']}-е число',
      'y' => 'раз в год',
      _ => 'повтор',
    };
    if (r['until'] != null) {
      final d = parseYmd(r['until'] as String)!;
      s += ' до ${d.day}.${d.month.toString().padLeft(2, '0')}';
    }
    if (r['count'] != null) s += ', ${r['count']} раз';
    return s;
  }

  static String _weekly(Map<String, dynamic> r) {
    final days = ((r['days'] as List?) ?? const []).map((x) => (x as num).toInt()).toList()..sort();
    if (days.length == 7) return 'каждый день';
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) return 'по будням';
    if (days.length == 2 && days.contains(6) && days.contains(7)) return 'по выходным';
    if (days.length == 1) return 'каждую неделю, ${_wd[days.first - 1]}';
    return 'по ${days.map((d) => _wd[d - 1]).join(', ')}';
  }

  static String _days(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }

  static DateTime _step(Map<String, dynamic> r, DateTime d) {
    final n = (r['n'] as num?)?.toInt() ?? 1;
    switch (r['t']) {
      case 'w':
        final days = ((r['days'] as List?) ?? const []).map((x) => (x as num).toInt()).toSet();
        if (days.isEmpty) return d.add(const Duration(days: 7));
        var x = d;
        for (var i = 0; i < 8; i++) {
          x = DateTime(x.year, x.month, x.day + 1);
          if (days.contains(x.weekday)) return x;
        }
        return x;
      case 'm':
        final md = (r['md'] as num?)?.toInt() ?? d.day;
        final y = d.month == 12 ? d.year + 1 : d.year;
        final m = d.month == 12 ? 1 : d.month + 1;
        final last = DateTime(y, m + 1, 0).day;
        return DateTime(y, m, md > last ? last : md);
      case 'y':
        return DateTime(d.year + 1, d.month, d.day);
      default:
        return DateTime(d.year, d.month, d.day + n);
    }
  }

  /// Следующий срок после выполнения. null — повторы закончились.
  static DateTime? next(Map<String, dynamic> r, DateTime due, DateTime doneOn, {int doneCount = 0}) {
    final today = dayOf(doneOn);
    final count = (r['count'] as num?)?.toInt();
    if (count != null && doneCount + 1 >= count) return null;
    DateTime x;
    if (r['t'] == 'a') {
      x = DateTime(today.year, today.month, today.day + ((r['n'] as num?)?.toInt() ?? 1));
    } else {
      x = _step(r, dayOf(due));
      // Пропущенные повторы не копятся: следующий срок — после сегодняшнего дня.
      var guard = 0;
      while (!x.isAfter(today) && guard++ < 2000) {
        x = _step(r, x);
      }
    }
    final until = parseYmd(r['until'] as String?);
    if (until != null && x.isAfter(until)) return null;
    return x;
  }
}
