// Заполняет базу примерами для скриншотов: ZHIZN_DB=путь flutter test tool/seed_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/data/models.dart';
import 'package:zhizn/data/store.dart';
import 'package:zhizn/logic/schedule.dart';
import 'package:zhizn/services/life.dart';
import 'dart:convert';

void main() {
  test('seed', () {
    final path = Platform.environment['ZHIZN_DB']!;
    final store = Store.open(path);
    final data = Schedule.extractData(File('test/fixtures/fkm.html').readAsStringSync());
    store.setKv('schedule_data', jsonEncode(data));
    store.setKv('schedule_at', DateTime.now().toIso8601String());
    final life = Life(store, filesDir: File(path).parent.path);
    life.capture('Постирать постельное\nУбраться в комнате\nПрактикум по ОРП рукописно\nПрактикум по Суд. бухгалтерии\nПрактикум по Хоз. процессу\nДиплом');
    life.capture('Позвонить в автошколу завтра в 15:00');
    life.capture('🔴 Сдать реферат по АХДП сегодня');
    life.capture('Зал по понедельникам и средам в 18:00');
    life.capture('обед 7,5');
    final t = dayOf(DateTime.now());
    for (final h in ['Протеин', 'Креатин', 'Витамин D', 'Скороговорки 10 мин', 'Сон до 23:30']) {
      final id = store.create(Kinds.habit, {'title': h, 'sphere': h.startsWith('Скор') ? 'self' : 'health', 'order': 0});
      for (var i = 1; i < 14; i++) {
        final d = t.subtract(Duration(days: i));
        store.patch(id, {'m:${ymd(d)}': (i * h.length) % 5 == 0 ? '✗' : ((i + h.length) % 7 == 0 ? '–' : '✓')});
      }
    }
    store.create(Kinds.question, {'text': 'Как часто стирать постельное?', 'options': ['Раз в неделю', 'Раз в 2 недели']});
    store.update('digest:${ymd(t)}:morning', Kinds.digest, {'text': 'Начни с реферата по АХДП до ВУЗа — 30 минут хватит на план. Вечером — практикумы, они короткие.'});
    final done = store.create(Kinds.task, {'title': 'Купить продукты', 'due': ymd(t), 'sphere': 'home'});
    life.complete(life.task(done)!);
  });
}
