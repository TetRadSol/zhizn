import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/data/models.dart';
import 'package:zhizn/data/store.dart';
import 'package:zhizn/logic/planner.dart';
import 'package:zhizn/logic/schedule.dart';
import 'package:zhizn/services/jarvis.dart';
import 'package:zhizn/services/life.dart';
import 'package:zhizn/services/mcp.dart';

Life newLife() => Life(Store.memory(deviceId: 'pc-a'), filesDir: Directory.systemTemp.createTempSync('zh').path);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('План дня', () {
    final day = DateTime(2026, 10, 22); // четверг
    Task task(Store s, Map<String, dynamic> f) => Task(s.get(s.create(Kinds.task, f))!);

    test('дела встают в свободные окна после ВУЗа, как можно раньше', () {
      final s = Store.memory();
      final lessons = [parseLesson(day, 1, 'ППФП т. 1 пр Ткачев В.С. спорт.городок'), parseLesson(day, 4, 'ОРП т. 1 Лекция Гаврилюк М.Н. Л/з № 3 МАШ')];
      final a = task(s, {'title': 'Постирать', 'due': '2026-10-22', 'dur': 60});
      final b = task(s, {'title': 'Реферат', 'due': '2026-10-25', 'dur': 90});
      final plan = planDay(day: day, now: DateTime(2026, 10, 22, 6), tasks: [a, b], lessons: lessons);
      final placed = plan.slots.where((x) => x.task != null).toList();
      expect(placed.map((x) => x.task!.title), ['Постирать', 'Реферат'], reason: 'будущее дело тоже ставится сегодня');
      // до ВУЗа окно 6:30–7:30 (первая пара 8:30 минус дорога, ВУЗ с 8:00 → с 7:30)
      expect(placed.first.start, DateTime(2026, 10, 22, 6, 30));
      // реферат 90 минут не влезает утром — после ВУЗа (16:00, последняя пара до 15:40 + дорога = 16:10)
      expect(placed[1].start.isAfter(DateTime(2026, 10, 22, 16)), isTrue);
      expect(plan.overflow, isEmpty);
    });

    test('перегруз: обязательное, что не помещается, — в списке переноса', () {
      final s = Store.memory();
      final tasks = [for (var i = 0; i < 12; i++) task(s, {'title': 'Дело $i', 'due': '2026-10-22', 'dur': 120})];
      final plan = planDay(day: day, now: DateTime(2026, 10, 22, 6), tasks: tasks, lessons: const []);
      expect(plan.overflow, isNotEmpty);
    });

    test('форс-мажор занимает день целиком', () {
      final life = newLife();
      final t = life.store.create(Kinds.task, {'title': 'Сдать реферат', 'due': ymd(life.today.add(const Duration(days: 1)))});
      final moved = life.forceMajeure('Наряд', life.today, life.today.add(const Duration(days: 1)));
      expect(moved.map((x) => x.id), [t]);
      expect(life.task(t)!.due, life.today.add(const Duration(days: 2)));
      expect(life.dayPlan().busyReason, 'Наряд');
    });
  });

  group('Джарвис: применение ответа', () {
    test('уточняет, создаёт, спрашивает; лишнее отбрасывает; ничего не удаляет', () {
      final life = newLife();
      final r = life.capture('Диплом\nПостирать постельное');
      final brain = JarvisBrain(life);
      final input = brain.buildInput(DateTime.now());
      final rec = (input['records'] as List).first as Map;
      expect(rec['made'], isNotEmpty);
      final taskId = r.created.firstWhere((id) => life.store.get(id)!.kind == Kinds.task);

      final report = brain.apply(
        {
          'changes': [
            {'op': 'update', 'id': taskId, 'fields': {'dur': 40, 'energy': 'low', 'done': true, 'prio': 'zzz', 'steps': ['Собрать', 'Запустить']}, 'why': 'стирка ~40 минут'},
            {'op': 'create', 'kind': 'task', 'fields': {'title': 'Выбрать тему диплома', 'due': '2026-11-01', 'sphere': 'study'}, 'record': r.captureId, 'why': 'первый шаг'},
            {'op': 'delete', 'id': taskId},
          ],
          'questions': [{'text': 'Как часто стирать постельное?', 'options': ['Раз в неделю', 'Раз в 2 недели'], 'task': taskId}],
          'records_done': [r.captureId],
          'evening': 'Хороший день.',
        },
        DateTime.now(),
        sentRecords: {r.captureId},
        sentAnswers: const {},
      );
      final t = life.task(taskId)!;
      expect(t.duration, 40);
      expect(t.energy, 'low');
      expect(t.done, isFalse, reason: 'Джарвис не отмечает сделанным');
      expect(t.prio, isNull, reason: 'неверная важность отброшена');
      expect(t.steps.map((s) => s['t']), ['Собрать', 'Запустить']);
      expect(t.jarvisNote, 'стирка ~40 минут');
      expect(report.rejected, containsAll(['done=true', 'prio=zzz']));
      expect(life.tasks.any((x) => x.title == 'Выбрать тему диплома'), isTrue);
      expect(life.openQuestions.single['options'], ['Раз в неделю', 'Раз в 2 недели']);
      expect(Capture(life.store.get(r.captureId)!).status, 'jarvis');
      expect(life.digest(life.today, 'evening')!['text'], 'Хороший день.');
      expect(brain.pendingRecords(), isEmpty);
    });

    test('ответ с текстом вокруг JSON всё равно читается', () {
      expect(JarvisBrain.extractJson('Вот:\n```json\n{"changes": []}\n```'), {'changes': []});
      expect(JarvisBrain.extractJson('нет json'), isNull);
    });

    test('полный запуск с поддельным Claude Code', () async {
      if (Platform.isWindows) return;
      final life = newLife();
      life.capture('Убраться в комнате');
      final fake = File('${life.filesDir}/claude')
        ..writeAsStringSync('''#!/bin/sh
cat > prompt.txt
test -f input.json || exit 3
grep -q "Ты — Джарвис" prompt.txt || exit 4
ID=\$(grep -o '"id": "ca[^"]*"' input.json | head -1 | cut -d'"' -f4)
printf '{"type":"result","is_error":false,"result":"{\\\\"questions\\\\":[{\\\\"text\\\\":\\\\"Когда удобно?\\\\"}],\\\\"records_done\\\\":[\\\\"%s\\\\"]}"}' "\$ID"
''');
      await Process.run('chmod', ['+x', fake.path]);
      final j = Jarvis(life)..claudePathOverride = fake.path;
      final r = await j.run();
      expect(j.lastError, isNull);
      expect(r!.questions, 1);
      expect(r.records, 1);
      expect(Jarvis.lastRun(life)!.ok, isTrue);
    });
  });

  group('Коннектор Claude Desktop', () {
    test('initialize, список инструментов, поиск и запись', () {
      final life = newLife();
      final mcp = Mcp(life);
      expect(mcp.handle({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}})!['result']['serverInfo']['name'], 'zhizn');
      expect(mcp.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}), isNull);
      final tools = (mcp.handle({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'})!['result']['tools'] as List).map((t) => t['name']);
      expect(tools, containsAll(['search', 'add', 'day', 'list_tasks']));

      Map<String, dynamic> call(String name, Map<String, dynamic> args) {
        final r = mcp.handle({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': name, 'arguments': args}})!['result'] as Map;
        expect(r['isError'], isNot(true), reason: '${r['content']}');
        return {'v': jsonDecode((r['content'] as List).first['text'] as String)};
      }

      call('add', {'text': 'Позвонить в автошколу завтра в 15:00'});
      final found = call('search', {'query': 'автошкол'})['v'] as Map;
      expect(found['found'], greaterThan(0));
      final day = call('day', {})['v'] as Map;
      expect(day['date'], ymd(life.today));
    });
  });
}
