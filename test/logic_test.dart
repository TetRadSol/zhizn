import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/data/models.dart';
import 'package:zhizn/logic/parser.dart';
import 'package:zhizn/logic/recurrence.dart';
import 'package:zhizn/logic/schedule.dart';

void main() {
  // Четверг, 22 октября 2026, 19:00
  final now = DateTime(2026, 10, 22, 19);
  final schedule = Schedule.fromData(
    Schedule.extractData(File('test/fixtures/fkm.html').readAsStringSync()),
    '3102',
  );
  final parser = Parser(now: now, schedule: schedule);
  Parsed one(String s) => parser.parseOne(s);

  group('Расписание', () {
    test('данные группы 3102 читаются со страницы', () {
      expect(schedule.byDate.length, greaterThan(90));
      expect(schedule.on(DateTime(2026, 9, 1)).first.raw, startsWith('День знаний'));
    });

    test('строка пары делится на части', () {
      final l = parseLesson(DateTime(2026, 9, 1), 2, 'ППФП т. 3.1 пр Ткачев В.С. Седнев С.М. спорт.городок');
      expect(l.subject, 'ППФП');
      expect(l.topic, 'т. 3.1');
      expect(l.type, 'практика');
      expect(l.teachers, ['Ткачев В.С.', 'Седнев С.М.']);
      expect(l.place, 'спорт.городок');
      expect(l.start, '10:00');
    });

    test('время из строки заменяет время пары', () {
      final l = parseLesson(DateTime(2026, 10, 16), 5,
          '17.20 - 20.10 Организация огневой подготовки в ОВД т.6 пр Федоренко А.С. Юшкевич А.Н. Тир МАШ');
      expect(l.start, '17:20');
      expect(l.end, '20:10');
      expect(l.subject, 'Организация огневой подготовки в ОВД');
      expect(l.place, 'Тир МАШ');
    });

    test('зачёты находятся', () {
      final l = parseLesson(DateTime(2026, 12, 24), 2, '10.00 СЭС Зачет Сауткин И.В. ауд. 2-408 ФКМ');
      expect(l.type, 'зачёт');
      expect(l.subject, 'СЭС');
      expect(l.isExam, isTrue);
      expect(schedule.exams(now), isNotEmpty);
    });

    test('сокращения предметов совпадают', () {
      expect(subjectMatchLength(tokenize('Практикум по ОРП рукописно'), 'Оперативно-розыскная психология'), 1);
      expect(subjectMatchLength(tokenize('Практикум по Суд. бухгалтерии'), 'Судебная бухгалтерия'), 2);
      expect(subjectMatchLength(tokenize('Практикум по Хоз. процессу'), 'Хозяйственный процесс'), 2);
      expect(subjectMatchLength(tokenize('в сб'), 'Судебная бухгалтерия'), 0);
    });
  });

  group('Ваши примеры из ТЗ', () {
    test('Постирать постельное → Дом', () {
      final p = one('Постирать постельное');
      expect(p.kind, 'task');
      expect(p.sphere, 'home');
      expect(p.title, 'Постирать постельное');
    });

    test('Убраться в комнате → Дом', () {
      final p = one('Убраться в комнате');
      expect(p.sphere, 'home');
      expect(p.title, 'Убраться в комнате');
    });

    for (final s in ['Практикум по ОРП рукописно', 'Практикум по Суд. бухгалтерии', 'Практикум по Хоз. процессу']) {
      test('$s → ДЗ к ближайшей паре, срок накануне', () {
        final p = one(s);
        expect(p.type, 'hw');
        expect(p.sphere, 'study');
        expect(p.lessonRef, isNotNull);
        final lesson = schedule.byRef(p.lessonRef!)!;
        expect(lesson.startAt.isAfter(now), isTrue);
        final eve = lesson.date.subtract(const Duration(days: 1));
        expect(p.due, eve.isBefore(dayOf(now)) ? dayOf(now) : eve);
      });
    }

    test('Диплом → цель', () {
      final p = one('Диплом');
      expect(p.kind, 'goal');
      expect(p.sphere, 'study');
    });
  });

  group('Даты и время', () {
    test('завтра в 15:00', () {
      final p = one('Позвонить в автошколу завтра в 15:00');
      expect(p.due, DateTime(2026, 10, 23));
      expect(p.time, '15:00');
      expect(p.title, 'Позвонить в автошколу');
      expect(p.sphere, 'auto');
    });

    test('в пятницу к 15.00', () {
      final p = one('Сдать реферат в пятницу к 15.00');
      expect(p.due, DateTime(2026, 10, 23));
      expect(p.time, '15:00');
      expect(p.title, 'Сдать реферат');
    });

    test('через 3 дня', () {
      expect(one('Забрать справку через 3 дня').due, DateTime(2026, 10, 25));
      expect(one('Забрать справку через неделю').due, DateTime(2026, 10, 29));
    });

    test('до 5 ноября — сдача', () {
      final p = one('Сдать курсовую до 5 ноября');
      expect(p.due, DateTime(2026, 11, 5));
      expect(p.type, 'deadline');
    });

    test('числом: 30.10', () {
      expect(one('Вождение 30.10 в 9 утра').due, DateTime(2026, 10, 30));
      expect(one('Вождение 30.10 в 9 утра').time, '09:00');
      expect(one('Вождение 30.10 в 9 утра').type, 'event');
    });

    test('с 18 до 20', () {
      final p = one('Зал с 18 до 20');
      expect(p.time, '18:00');
      expect(p.duration, 120);
      expect(p.sphere, 'health');
    });

    test('длительность', () {
      expect(one('Читать книгу 30 мин').duration, 30);
      expect(one('Убраться 1,5 часа').duration, 90);
    });

    test('число без часов не время', () {
      final p = one('Отжимания в 3 подхода');
      expect(p.time, isNull);
      expect(p.title, 'Отжимания в 3 подхода');
    });

    test('важность', () {
      expect(one('🔴 Оплатить автошколу').prio, Prio.red);
      expect(one('Оплатить автошколу срочно').prio, Prio.red);
      expect(one('🟢 Посмотреть фильм').prio, Prio.green);
    });
  });

  group('Повторы', () {
    test('каждый день', () {
      final p = one('Скороговорки каждый день');
      expect(p.repeat, Repeat.daily());
      expect(p.due, DateTime(2026, 10, 22));
      expect(p.title, 'Скороговорки');
    });

    test('по понедельникам и средам', () {
      final p = one('Зал по понедельникам и средам в 18:00');
      expect(p.repeat, Repeat.weekly([1, 3]));
      expect(p.due, DateTime(2026, 10, 26));
      expect(p.time, '18:00');
    });

    test('каждые 3 дня, 5 раз', () {
      final p = one('Полить цветы каждые 3 дня 5 раз');
      expect(p.repeat, {'t': 'd', 'n': 3, 'count': 5});
    });

    test('каждое 10 число', () {
      final p = one('Оплатить интернет каждое 10 число');
      expect(p.repeat, Repeat.monthly(10));
      expect(p.due, DateTime(2026, 11, 10));
    });

    test('следующий срок', () {
      final d = DateTime(2026, 10, 20);
      expect(Repeat.next(Repeat.daily(), d, now), DateTime(2026, 10, 23));
      expect(Repeat.next(Repeat.weekly([1, 3]), DateTime(2026, 10, 21), now), DateTime(2026, 10, 26));
      expect(Repeat.next(Repeat.afterDone(3), d, now), DateTime(2026, 10, 25));
      expect(Repeat.next(Repeat.monthly(31), DateTime(2026, 10, 31), DateTime(2026, 10, 31)), DateTime(2026, 11, 30));
      expect(Repeat.next({'t': 'd', 'n': 1, 'count': 2}, d, now, doneCount: 1), isNull);
      expect(Repeat.next({'t': 'd', 'n': 1, 'until': '2026-10-22'}, d, now), isNull);
    });
  });

  group('Запись делится на дела', () {
    test('по строкам и пунктам', () {
      final items = Parser.splitItems('- Постирать постельное\n2) Убраться в комнате; Диплом');
      expect(items, ['Постирать постельное', 'Убраться в комнате', 'Диплом']);
    });
  });

  group('Журнал и заметки', () {
    test('трата', () {
      final p = one('обед 7,5');
      expect(p.kind, 'journal');
      expect(p.type, 'money');
      expect(p.amount, 7.5);
    });
    test('тренировка', () {
      final p = one('жим 60 на 10');
      expect(p.kind, 'journal');
      expect(p.type, 'workout');
    });
    test('вес', () => expect(one('вес 72,5').amount, 72.5));
    test('идея', () {
      final p = one('Идея: вести дневник благодарности');
      expect(p.kind, 'note');
      expect(p.title, 'Вести дневник благодарности');
    });
    test('привычка', () {
      final p = one('привычка: протеин');
      expect(p.kind, 'habit');
      expect(p.sphere, 'health');
    });
  });
}
