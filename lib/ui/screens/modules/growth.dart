import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models.dart';
import '../../../data/store.dart';
import '../../../logic/finance.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';

Uri videoSearch(String q) => Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}');

/// Запасные задания, пока Джарвис не дал своё (меняются по дням).
const _fallback = <String, List<String>>{
  'Скороговорки': [
    'Карл у Клары украл кораллы — 10 раз медленно, 10 раз быстро, с карандашом в зубах',
    'Шла Саша по шоссе и сосала сушку — по 5 раз шёпотом, обычно и громко',
    'Ехал Грека через реку — с выделением каждой согласной',
    'На дворе трава, на траве дрова — 3 темпа, запишите себя на диктофон',
  ],
  'Риторика': [
    'Расскажите за 1 минуту, почему ваша профессия важна. Без «э-э», с паузами',
    'Объясните тему сегодняшней пары так, будто слушателю 12 лет',
    'Прочитайте вслух абзац текста с интонацией и паузами, запишите на диктофон',
    'Три аргумента «за» и три «против» любого решения — вслух, по 20 секунд',
  ],
  'Уверенность': [
    'Сегодня первым поздоровайтесь с тремя людьми и посмотрите в глаза',
    '2 минуты «позы силы» перед важным делом, ровная спина весь день',
    'Задайте один вопрос преподавателю или незнакомцу',
    'Запишите 3 вещи, которые сегодня получились',
  ],
  'Каллиграфия': [
    'Прописи: строчные «а, о, с» — по строке, наклон 55°, без спешки',
    'Соединения букв: «ла, ма, на» — по 2 строки',
    'Перепишите одно предложение новым почерком 3 раза, сравните',
    'Заглавные буквы: «А, Б, В» — по строке',
  ],
  'Substack': [
    'Прочитайте одну статью и запишите главную мысль в заметку',
    'Найдите автора по своей теме и подпишитесь',
  ],
};

String fallbackFor(String title, DateTime day) {
  for (final e in _fallback.entries) {
    if (title.contains(e.key)) return e.value[day.difference(DateTime(2026)).inDays % e.value.length];
  }
  return 'Выполните практику ${title.toLowerCase()} 10–15 минут';
}

/// Саморазвитие: практики-привычки, задание на каждый день от Джарвиса.
class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Саморазвитие')),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, null), child: const Icon(Icons.add)),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final today = S.life.today;
          final ps = S.life.store.ofKind(Kinds.practice).toList()..sort((a, b) => ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
          final cs = Theme.of(context).colorScheme;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text('Каждый день — новое упражнение. Джарвис подбирает его вечером на завтра; пока его нет — даю своё.', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            for (final p in ps)
              Builder(builder: (context) {
                final a = S.life.store.get('assign:${p.id}:${ymd(today)}');
                final text = (a?['text'] as String?) ?? fallbackFor('${p['title']}', today);
                final mark = p['m:${ymd(today)}'] as String?;
                var streak = 0;
                for (var i = 0; i < 365; i++) {
                  final m = p['m:${ymd(today.subtract(Duration(days: i)))}'];
                  if (m == '✓') {
                    streak++;
                  } else if (i > 0) {
                    break;
                  }
                }
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${p['title']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                        if (streak > 1) Text('🔥$streak  '),
                        Text('${p['minutes'] ?? 10} мин', style: TextStyle(color: cs.onSurfaceVariant)),
                        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.more_vert), onPressed: () => _edit(context, p)),
                      ]),
                      const SizedBox(height: 4),
                      Text('${a != null ? '🤖 ' : ''}$text'),
                      const SizedBox(height: 8),
                      Row(children: [
                        FilledButton.tonalIcon(
                          icon: Icon(mark == '✓' ? Icons.check_circle : Icons.check),
                          label: Text(mark == '✓' ? 'Сделано' : 'Отметить'),
                          onPressed: () => S.life.store.patch(p.id, {'m:${ymd(today)}': mark == '✓' ? null : '✓'}),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Видео'),
                          onPressed: () => launchUrl((a?['link'] as String?) != null ? Uri.parse(a!['link'] as String) : videoSearch('${p['title']} упражнения'), mode: LaunchMode.externalApplication),
                        ),
                      ]),
                    ]),
                  ),
                );
              }),
          ]);
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, Entity? p) async {
    final title = TextEditingController(text: p?['title'] as String? ?? '');
    final about = TextEditingController(text: p?['about'] as String? ?? '');
    final minutes = TextEditingController(text: '${p?['minutes'] ?? 10}');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(p == null ? 'Новая практика' : 'Практика'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Название', hintText: '🎸 Гитара')),
          TextField(controller: about, decoration: const InputDecoration(labelText: 'Чего хочу добиться (для Джарвиса)')),
          TextField(controller: minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Минут в день')),
        ]),
        actions: [
          if (p != null) TextButton(onPressed: () {
            S.life.store.delete(p.id);
            Navigator.pop(context);
          }, child: const Text('Удалить')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              final f = {'title': title.text.trim(), 'about': about.text.trim(), 'minutes': int.tryParse(minutes.text) ?? 10};
              if (p == null) {
                S.life.store.create(Kinds.practice, {...f, 'order': S.life.store.ofKind(Kinds.practice).length});
              } else {
                S.life.store.patch(p.id, f);
              }
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

// ---------- Отдых с пользой ----------

const recCats = {
  'break': '☕ Перерыв на паре',
  'watch': '🎬 Смотреть',
  'read': '📖 Читать',
  'self': '🧭 Для себя',
};

/// Что можно сделать за 5 минут перерыва.
const breakIdeas = [
  ('Скороговорка дня', 'Повторить 5 раз, ускоряясь'),
  ('Мелкая моторика', 'Покрутить ручку между пальцами, по 30 секунд каждой рукой'),
  ('Разминка шеи и плеч', '10 кругов плечами, 10 наклонов головы'),
  ('Дыхание 4-7-8', 'Вдох 4 с, задержка 7 с, выдох 8 с — 4 раза'),
  ('Прописи', 'Строка букв новым почерком на полях тетради'),
  ('Английский', '5 новых слов из темы пары'),
  ('Статья Substack', 'Прочитать 1 короткую заметку'),
  ('Глаза', 'Посмотреть вдаль 20 секунд, поморгать'),
];

class LeisureScreen extends StatelessWidget {
  const LeisureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: recCats.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Отдых с пользой'),
          bottom: TabBar(isScrollable: true, tabs: [for (final c in recCats.values) Tab(text: c)]),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Ещё идей'),
              onPressed: () {
                S.life.store.update('rec_request', 'flag', {'at': DateTime.now().toIso8601String()});
                toast(context, 'Джарвис подберёт новое при следующем разборе');
              },
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: S.life,
          builder: (context, _) {
            final recs = S.life.store.ofKind(Kinds.rec).where((r) => r['status'] != 'hidden').toList()
              ..sort((a, b) => ((b['created'] as String?) ?? '').compareTo((a['created'] as String?) ?? ''));
            return TabBarView(children: [
              for (final c in recCats.keys) _RecList(cat: c, recs: recs.where((r) => r['cat'] == c || (c == 'self' && r['cat'] == 'dating')).toList()),
            ]);
          },
        ),
      ),
    );
  }
}

class _RecList extends StatelessWidget {
  const _RecList({required this.cat, required this.recs});
  final String cat;
  final List<Entity> recs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (cat == 'break')
        for (final (t, d) in breakIdeas) Card(child: ListTile(leading: const Text('⏱'), title: Text(t), subtitle: Text(d))),
      if (recs.isEmpty && cat != 'break')
        EmptyHint(
          icon: Icons.auto_awesome,
          title: 'Пока пусто',
          text: cat == 'self'
              ? 'Здесь будут советы Джарвиса: что улучшить в себе, общение и знакомства, полезные привычки. Нажмите «Ещё идей».'
              : 'Нажмите «Ещё идей» — Джарвис подберёт по вашим интересам: спецслужбы, развитие, интервью.',
        ),
      for (final r in recs)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['title']}', style: TextStyle(fontWeight: FontWeight.w700, decoration: r['status'] == 'done' ? TextDecoration.lineThrough : null)),
              if ('${r['why'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['why']}', style: TextStyle(color: cs.onSurfaceVariant))),
              Row(children: [
                if (r['link'] != null)
                  TextButton.icon(onPressed: () => launchUrl(Uri.parse(r['link'] as String), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Открыть')),
                const Spacer(),
                IconButton(tooltip: 'Нравится', onPressed: () => S.life.store.patch(r.id, {'like': r['like'] == true ? null : true}), icon: Icon(r['like'] == true ? Icons.thumb_up : Icons.thumb_up_outlined, size: 20)),
                IconButton(tooltip: 'Не моё — скрыть', onPressed: () => S.life.store.patch(r.id, {'status': 'hidden', 'like': false}), icon: const Icon(Icons.thumb_down_outlined, size: 20)),
                IconButton(tooltip: 'Сделано', onPressed: () => S.life.store.patch(r.id, {'status': r['status'] == 'done' ? 'new' : 'done'}), icon: Icon(r['status'] == 'done' ? Icons.check_circle : Icons.check, size: 20)),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

// ---------- Автошкола ----------

class AutoSchoolScreen extends StatelessWidget {
  const AutoSchoolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Автошкола')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final today = S.life.today;
          final t = S.life.store.get('tickets');
          final total = (t?['total'] as num?)?.toInt() ?? 40;
          final ok = List.generate(total, (i) => t?['t:${i + 1}']).where((m) => m == '✓').length;
          final bad = List.generate(total, (i) => t?['t:${i + 1}']).where((m) => m == '✗').length;
          final drives = S.life.tasks.where((x) => x.title.toLowerCase().contains('вожден')).toList();
          final drivesDone = drives.fold<int>(0, (a, x) => a + x.e.f.entries.where((e) => e.key.startsWith('c:') && e.value == true).length + (x.done ? 1 : 0));
          final nextDrive = drives.where((x) => !x.done && x.due != null && !x.due!.isBefore(today)).toList()..sort((a, b) => a.due!.compareTo(b.due!));
          final events = S.life.store.ofKind(Kinds.autoEvent).toList()..sort((a, b) => ((a['date'] as String?) ?? '').compareTo((b['date'] as String?) ?? ''));
          final paid = events.where((e) => e['type'] == 'payment').fold(0.0, (a, e) => a + ((e['amount'] as num?)?.toDouble() ?? 0));
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Card(child: ListTile(title: Text('$drivesDone'), subtitle: const Text('занятий вождения')))),
              Expanded(child: Card(child: ListTile(title: Text('$ok / $total'), subtitle: const Text('билетов решено')))),
              Expanded(child: Card(child: ListTile(title: Text(money(paid)), subtitle: const Text('оплачено')))),
            ]),
            if (nextDrive.isNotEmpty)
              ListTile(contentPadding: EdgeInsets.zero, leading: const Text('🚗', style: TextStyle(fontSize: 22)), title: Text('Следующее вождение: ${dayLabel(nextDrive.first.due!)}${nextDrive.first.time != null ? ', ${nextDrive.first.time}' : ''}')),
            SectionTitle(
              'Билеты ПДД · ошибок $bad',
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
              trailing: TextButton(onPressed: () => _setTotal(context, total), child: Text('Всего: $total')),
            ),
            Text('Нажмите на билет: ✓ без ошибок → ✗ с ошибками → пусто.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (var i = 1; i <= total; i++)
                Builder(builder: (context) {
                  final m = t?['t:$i'] as String?;
                  return InkWell(
                    onTap: () => S.life.store.update('tickets', Kinds.ticket, {'t:$i': switch (m) { null => '✓', '✓' => '✗', _ => null }}),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: m == '✓' ? const Color(0xFF2E9E6A) : (m == '✗' ? cs.error : cs.surfaceContainerHigh),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$i', style: TextStyle(color: m == null ? null : Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  );
                }),
            ]),
            TextButton.icon(onPressed: () => launchUrl(Uri.parse('https://www.google.com/search?q=${Uri.encodeQueryComponent('билеты ПДД Беларусь онлайн')}'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Решать билеты онлайн')),
            SectionTitle(
              'Экзамены и оплаты',
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
              trailing: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Добавить'), onPressed: () => _addEvent(context)),
            ),
            for (final e in events)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(e['type'] == 'payment' ? '💳' : '📝', style: const TextStyle(fontSize: 22)),
                title: Text('${e['title']}${e['amount'] != null ? ' · ${money((e['amount'] as num).toDouble())}' : ''}'),
                subtitle: Text(e['date'] == null ? '' : () {
                  final d = parseYmd(e['date'] as String)!;
                  final left = d.difference(today).inDays;
                  return '${dayLabel(d)}${e['type'] != 'payment' && left >= 0 ? ' · через $left дн.' : ''}${e['result'] != null ? ' · ${e['result']}' : ''}';
                }()),
                trailing: e['type'] == 'payment' ? null : PopupMenuButton<String>(
                  onSelected: (v) => S.life.store.patch(e.id, {'result': v}),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'сдал ✓', child: Text('Сдал')), PopupMenuItem(value: 'не сдал ✗', child: Text('Не сдал'))],
                ),
                onLongPress: () => S.life.store.delete(e.id),
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _setTotal(BuildContext context, int cur) async {
    final c = TextEditingController(text: '$cur');
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Сколько всего билетов'),
        content: TextField(controller: c, keyboardType: TextInputType.number),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK'))],
      ),
    );
    final n = int.tryParse(r ?? '');
    if (n != null && n > 0 && n <= 300) S.life.store.update('tickets', Kinds.ticket, {'total': n});
  }

  Future<void> _addEvent(BuildContext context) async {
    var type = 'exam';
    final title = TextEditingController();
    final amount = TextEditingController();
    var date = S.life.today;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Автошкола'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'exam', label: Text('Экзамен')), ButtonSegment(value: 'payment', label: Text('Оплата'))],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            TextField(controller: title, decoration: InputDecoration(labelText: type == 'exam' ? 'Какой' : 'За что', hintText: type == 'exam' ? 'Внутренний: теория' : 'Обучение, 2 часть')),
            if (type == 'payment') TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Сумма, Br')),
            TextButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (d != null) setState(() => date = d);
              },
              child: Text('Дата: ${dayLabel(date)}'),
            ),
          ]),
          actions: [
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                final a = double.tryParse(amount.text.replaceAll(',', '.'));
                S.life.store.create(Kinds.autoEvent, {'type': type, 'title': title.text.trim(), 'date': ymd(date), 'amount': ?a});
                if (type == 'payment' && a != null) {
                  S.life.store.create(Kinds.money, {'date': ymd(date), 'type': 'expense', 'cat': 'auto', 'amount': a, 'currency': 'Br', 'note': 'Автошкола: ${title.text.trim()}'});
                }
                if (type == 'exam') {
                  S.life.store.create(Kinds.task, {'title': 'Экзамен в автошколе: ${title.text.trim()}', 'due': ymd(date), 'type': 'deadline', 'sphere': 'auto', 'prio': Prio.red});
                }
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
