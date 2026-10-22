import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/data/models.dart';
import 'package:zhizn/data/store.dart';
import 'package:zhizn/logic/excel_import.dart';
import 'package:zhizn/logic/finance.dart';
import 'package:zhizn/logic/motivation.dart';
import 'package:zhizn/services/jarvis.dart';
import 'package:zhizn/services/life.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = DateTime(2026, 10, 22);

  test('идеальный день, серия, опыт и награды', () {
    final s = Store.memory();
    final a = s.create(Kinds.habit, {'title': 'A'});
    final b = s.create(Kinds.habit, {'title': 'B'});
    for (var i = 0; i < 3; i++) {
      final d = ymd(today.subtract(Duration(days: i)));
      s.patch(a, {'m:$d': '✓'});
      s.patch(b, {'m:$d': i == 1 ? '–' : '✓'});
    }
    final m = Motivation(s, today);
    expect(m.ideal(today), isTrue);
    expect(m.idealDays, 3);
    expect(m.bestStreak, 3);
    expect(m.totalChecks, 5);
    expect(m.xp, 5 * 5 + 3 * 30);
    s.create(Kinds.reward, {'title': 'Кофе', 'cond': 'streak', 'threshold': 3});
    expect(m.value('streak'), 3);
  });

  test('прогресс целей: накопления, этапы', () {
    final s = Store.memory();
    final g = s.create(Kinds.goal, {'title': 'Накопить', 'source': 'savings', 'target': '1000'});
    s.create(Kinds.money, {'date': '2026-10-22', 'type': 'saving', 'amount': 250.0, 'currency': 'Br'});
    expect(Motivation(s, today).goal(s.get(g)!).progress, 0.25);
    final h = s.create(Kinds.goal, {'title': 'Диплом', 'stages': [{'t': 'Тема', 'd': true}, {'t': 'Глава 1', 'd': false}]});
    expect(Motivation(s, today).goal(s.get(h)!).progress, 0.5);
  });

  test('финансы за месяц и награды/практики по умолчанию', () {
    final s = Store.memory();
    s.create(Kinds.money, {'date': '2026-10-22', 'type': 'expense', 'cat': 'food', 'amount': 7.5, 'currency': 'Br'});
    s.create(Kinds.money, {'date': '2026-10-21', 'type': 'income', 'cat': 'stipend', 'amount': 120.0, 'currency': 'Br'});
    final mm = monthMoney(s, 2026, 10);
    expect((mm.income, mm.expense, mm.balance), (120.0, 7.5, 112.5));
    ensureDefaults(s);
    expect(s.ofKind(Kinds.reward).length, 8);
    expect(s.ofKind(Kinds.practice).length, 5);
    ensureDefaults(s);
    expect(s.ofKind(Kinds.reward).length, 8);
  });

  test('Джарвис: задания практик и рекомендации', () {
    final life = Life(Store.memory(), filesDir: '/tmp');
    ensureDefaults(life.store);
    final now = DateTime(2026, 10, 22, 21);
    final r = JarvisBrain(life).apply({
      'assignments': {'prc1': {'text': 'Карл у Клары — 3 темпа'}, 'нет такой': 'x'},
      'recommendations': [
        {'cat': 'watch', 'title': 'Фильм', 'why': 'про разведку', 'link': 'https://example.com'},
        {'cat': 'странное', 'title': 'Совет'},
      ],
    }, now, sentRecords: const {}, sentAnswers: const {});
    expect(r.rejected, isEmpty);
    expect(life.store.get('assign:prc1:2026-10-23')!['text'], 'Карл у Клары — 3 темпа');
    expect(life.store.ofKind(Kinds.rec).map((e) => e['cat']), containsAll(['watch', 'self']));
  });
}
