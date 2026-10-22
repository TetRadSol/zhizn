import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/data/models.dart';
import 'package:zhizn/data/store.dart';
import 'package:zhizn/logic/recurrence.dart';
import 'package:zhizn/services/life.dart';
import 'package:zhizn/services/reminders.dart';

/// Передать неотправленные изменения с одного устройства на другое — как через GitHub.
void exchange(Store from, Store to) {
  final ops = from.pendingOps();
  to.applyRemote(ops);
  from.markPushed(ops.map((o) => o.id));
}

void main() {
  group('Синхронизация', () {
    test('запись с телефона появляется на ноутбуке', () {
      final tel = Store.memory(deviceId: 'tel-a');
      final pc = Store.memory(deviceId: 'pc-b');
      final id = tel.create(Kinds.task, {'title': 'Постирать постельное', 'sphere': 'home'});
      exchange(tel, pc);
      expect(pc.get(id)!['title'], 'Постирать постельное');
      expect(pc.pendingOps(), isEmpty, reason: 'чужие изменения не отправляются повторно');
    });

    test('разные поля одной задачи не теряются', () {
      var t = 1000;
      final tel = Store.memory(deviceId: 'tel-a', clock: () => t);
      final pc = Store.memory(deviceId: 'pc-b', clock: () => t);
      final id = tel.create(Kinds.task, {'title': 'Реферат'});
      exchange(tel, pc);
      t = 2000;
      tel.patch(id, {'due': '2026-10-25'});
      t = 2001;
      pc.patch(id, {'prio': 'r'});
      exchange(tel, pc);
      exchange(pc, tel);
      for (final s in [tel, pc]) {
        expect(s.get(id)!['due'], '2026-10-25');
        expect(s.get(id)!['prio'], 'r');
      }
    });

    test('одно поле дважды — побеждает поздняя правка, старая в истории', () {
      var t = 1000;
      final tel = Store.memory(deviceId: 'tel-a', clock: () => t);
      final pc = Store.memory(deviceId: 'pc-b', clock: () => t);
      final id = pc.create(Kinds.task, {'title': 'A'});
      exchange(pc, tel);
      t = 3000;
      pc.patch(id, {'title': 'Поздняя'});
      t = 2000;
      tel.patch(id, {'title': 'Ранняя'});
      // порядок обмена не важен
      exchange(pc, tel);
      exchange(tel, pc);
      expect(tel.get(id)!['title'], 'Поздняя');
      expect(pc.get(id)!['title'], 'Поздняя');
      expect(tel.history(id).map((o) => o.value), containsAll(['Поздняя', 'Ранняя', 'A']));
    });

    test('повторное применение ничего не ломает', () {
      final tel = Store.memory(deviceId: 'tel-a');
      final pc = Store.memory(deviceId: 'pc-b');
      final id = tel.create(Kinds.task, {'title': 'X'});
      final ops = tel.pendingOps();
      pc.applyRemote(ops);
      pc.applyRemote(ops);
      expect(pc.ofKind(Kinds.task).length, 1);
      expect(pc.get(id)!['title'], 'X');
    });

    test('удаление и восстановление', () {
      final s = Store.memory(deviceId: 'pc-a');
      final id = s.create(Kinds.task, {'title': 'X'});
      s.delete(id);
      expect(s.get(id), isNull);
      s.restore(id);
      expect(s.get(id), isNotNull);
    });
  });

  group('Задачи', () {
    test('повторяющаяся задача после выполнения переходит на следующий раз', () {
      final life = Life(Store.memory(deviceId: 'pc-a'), filesDir: '/tmp');
      final today = dayOf(DateTime.now());
      final id = life.store.create(Kinds.task, {'title': 'Скороговорки', 'due': ymd(today), 'repeat': Repeat.daily()});
      life.complete(life.task(id)!);
      final t = life.task(id)!;
      expect(t.done, isFalse);
      expect(t.due, today.add(const Duration(days: 1)));
      expect(t.completedOn(today), isTrue);
      expect(life.doneToday().map((x) => x.id), contains(id));
    });

    test('запись создаёт дела и отменяется', () {
      final life = Life(Store.memory(deviceId: 'pc-a'), filesDir: '/tmp');
      final r = life.capture('Постирать постельное\nУбраться в комнате\nобед 7,5');
      expect(r.created.length, 3);
      expect(life.tasks.length, 2);
      expect(life.journal.length, 1);
      life.undoCapture(r);
      expect(life.tasks, isEmpty);
      expect(life.captures, isEmpty);
    });
  });

  group('Напоминания', () {
    test('на телефоне днём тишина, в 16:00 сводка', () {
      final life = Life(Store.memory(deviceId: 'tel-a'), filesDir: '/tmp');
      final now = DateTime(2026, 10, 22, 7); // четверг
      life.store.create(Kinds.task, {'title': 'Позвонить в автошколу', 'due': '2026-10-22', 'time': '12:00'});
      life.store.create(Kinds.task, {'title': 'Зал', 'due': '2026-10-22', 'time': '18:00'});
      final phone = planReminders(life, now, phone: true, days: 1);
      expect(phone.any((r) => r.body.contains('автошколу') && r.key.startsWith('task:')), isFalse);
      final quiet = phone.firstWhere((r) => r.key.startsWith('quiet:'));
      expect(quiet.at, DateTime(2026, 10, 22, 16));
      expect(quiet.body, contains('автошколу'));
      expect(phone.any((r) => r.body.contains('Зал') && r.at == DateTime(2026, 10, 22, 18)), isTrue);

      final pc = planReminders(life, now, phone: false, days: 1);
      expect(pc.any((r) => r.body.contains('автошколу') && r.at == DateTime(2026, 10, 22, 12)), isTrue);
    });

    test('план на день и итог', () {
      final life = Life(Store.memory(deviceId: 'tel-a'), filesDir: '/tmp');
      final plan = planReminders(life, DateTime(2026, 10, 22, 5), phone: true, days: 1);
      expect(plan.map((r) => r.at), containsAll([DateTime(2026, 10, 22, 6, 30), DateTime(2026, 10, 22, 21, 30)]));
    });
  });
}
