import '../data/models.dart';
import '../data/store.dart';

/// Категории из Excel-трекера (лист «Финансы»).
class MoneyCat {
  const MoneyCat(this.id, this.label, this.type, this.words);
  final String id;
  final String label;

  /// expense, income, saving
  final String type;
  final List<String> words;

  static const all = [
    MoneyCat('food', '🍔 Еда', 'expense', ['обед', 'ужин', 'завтрак', 'кофе', 'кафе', 'шаурм', 'перекус', 'еда', 'продукт', 'магазин', 'столов', 'доставк', 'пицц', 'чай', 'вода']),
    MoneyCat('transport', '🚌 Транспорт', 'expense', ['такси', 'проезд', 'автобус', 'метро', 'бензин', 'маршрутк', 'поезд', 'билет на']),
    MoneyCat('study', '🎓 Учёба', 'expense', ['учеб', 'тетрад', 'ручк', 'печат', 'ксерокс', 'методичк', 'канцел']),
    MoneyCat('auto', '🚗 Автошкола', 'expense', ['автошкол', 'вождени', 'инструктор', 'пдд']),
    MoneyCat('fun', '🎉 Развлечения', 'expense', ['кино', 'игр', 'концерт', 'бар', 'развлеч']),
    MoneyCat('clothes', '👕 Одежда', 'expense', ['одежд', 'кроссовк', 'футболк', 'куртк', 'джинс', 'обув']),
    MoneyCat('health', '💊 Здоровье', 'expense', ['аптек', 'врач', 'витамин', 'протеин', 'креатин', 'лекарств', 'омега', 'магни']),
    MoneyCat('phone', '📱 Связь и подписки', 'expense', ['связь', 'интернет', 'подписк', 'телефон', 'мобильн']),
    MoneyCat('sport', '🏋️ Спорт', 'expense', ['зал', 'абонемент', 'спорт']),
    MoneyCat('gifts', '🎁 Подарки', 'expense', ['подарок', 'подарки', 'цветы']),
    MoneyCat('home', '🏠 Дом / быт', 'expense', ['быт', 'хозтовар', 'уборк', 'порошок', 'шампун', 'мыло']),
    MoneyCat('other', '📦 Другое', 'expense', []),
    MoneyCat('stipend', '🎓 Стипендия', 'income', ['стипенди']),
    MoneyCat('job', '💼 Подработка', 'income', ['подработк', 'зарплат', 'заработ']),
    MoneyCat('parents', '👪 Родители / подарки', 'income', ['родител', 'мама дала', 'папа дал', 'подарили']),
    MoneyCat('other_in', '📦 Другое доход', 'income', ['доход', 'получил']),
    MoneyCat('saving', '🏦 Накопление', 'saving', ['отложил', 'отложить', 'копилк', 'накопл']),
  ];

  static MoneyCat byId(String? id) => all.firstWhere((c) => c.id == id, orElse: () => all.firstWhere((c) => c.id == 'other'));
}

/// Разбор «обед 7,5», «+50 стипендия», «отложил 20», «такси 5$».
({String type, String cat, double amount, String currency, String note})? parseMoney(String text) {
  final l = text.toLowerCase().trim();
  final m = RegExp(r'([+-]?)\s*(\d+(?:[.,]\d{1,2})?)\s*(br|byn|руб\.?|р\.?|\$|usd|долл\.?)?').firstMatch(l);
  if (m == null) return null;
  final amount = double.parse(m[2]!.replaceAll(',', '.'));
  final currency = (m[3] == r'$' || m[3] == 'usd' || (m[3]?.startsWith('долл') ?? false)) ? r'$' : 'Br';
  final note = text.replaceFirst(RegExp(r'[+-]?\s*\d+(?:[.,]\d{1,2})?\s*(br|byn|руб\.?|р\.?|\$|usd|долл\.?)?', caseSensitive: false), '').trim();
  MoneyCat? cat;
  for (final c in MoneyCat.all) {
    if (c.words.any((w) => l.contains(w))) {
      cat = c;
      break;
    }
  }
  if (m[1] == '+' && (cat == null || cat.type == 'expense')) cat = MoneyCat.byId('other_in');
  cat ??= MoneyCat.byId('other');
  return (type: cat.type, cat: cat.id, amount: amount, currency: currency, note: note);
}

class MonthMoney {
  double income = 0, expense = 0, saving = 0;
  final Map<String, double> byCat = {};
  double get balance => income - expense - saving;
}

List<Entity> moneyOf(Store s) => s.ofKind(Kinds.money).toList()
  ..sort((a, b) => ((b['date'] as String?) ?? '').compareTo((a['date'] as String?) ?? ''));

/// Итоги месяца в рублях (доллары считаются отдельно и в итог не входят).
MonthMoney monthMoney(Store s, int year, int month, {String currency = 'Br'}) {
  final r = MonthMoney();
  for (final e in s.ofKind(Kinds.money)) {
    final d = parseYmd(e['date'] as String?);
    if (d == null || d.year != year || d.month != month || (e['currency'] ?? 'Br') != currency) continue;
    final a = (e['amount'] as num?)?.toDouble() ?? 0;
    switch (e['type']) {
      case 'income':
        r.income += a;
      case 'saving':
        r.saving += a;
      default:
        r.expense += a;
        final c = (e['cat'] as String?) ?? 'other';
        r.byCat[c] = (r.byCat[c] ?? 0) + a;
    }
  }
  return r;
}

/// Всего накоплено (Br).
double totalSaved(Store s) => s
    .ofKind(Kinds.money)
    .where((e) => e['type'] == 'saving' && (e['currency'] ?? 'Br') == 'Br')
    .fold(0.0, (a, e) => a + ((e['amount'] as num?)?.toDouble() ?? 0));

String money(double v, [String cur = 'Br']) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');
  return cur == r'$' ? '\$$s' : '$s Br';
}
