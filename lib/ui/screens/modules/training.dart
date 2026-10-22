import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../data/store.dart';
import '../../../logic/training.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';
import 'health.dart';

/// Тренировки и питание: программы, журнал подходов, еда и вода.
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Тренировки и питание'),
          bottom: const TabBar(tabs: [Tab(text: 'Сегодня'), Tab(text: 'Программы'), Tab(text: 'Питание')]),
        ),
        body: ListenableBuilder(
          listenable: S.life,
          builder: (context, _) => const TabBarView(children: [_Today(), _Programs(), _Food()]),
        ),
      ),
    );
  }
}

List<Entity> _workouts() => S.life.store.ofKind(Kinds.workout).toList()
  ..sort((a, b) => '${b['date']}${b['created']}'.compareTo('${a['date']}${a['created']}'));

String _setText(Entity w) {
  if (w['seconds'] != null) return '${w['seconds']} сек';
  final sets = (w['sets'] as num?)?.toInt() ?? 1;
  final reps = w['reps'];
  final wt = w['weight'];
  return [if (wt != null) '$wt кг', if (reps != null) '× $reps', if (sets > 1) '× $sets подх.'].join(' ');
}

class _Today extends StatefulWidget {
  const _Today();
  @override
  State<_Today> createState() => _TodayState();
}

class _TodayState extends State<_Today> {
  final _c = TextEditingController();

  void _add([String? text]) {
    final t = (text ?? _c.text).trim();
    final w = parseWorkout(t);
    if (w == null) {
      toast(context, 'Не понял. Пример: «жим 60 на 10», «присед 80х5х3», «планка 60 сек»');
      return;
    }
    S.life.store.create(Kinds.workout, {
      'date': ymd(S.life.today),
      'exercise': w.exercise,
      'weight': ?w.weight,
      'reps': ?w.reps,
      'sets': w.sets,
      'seconds': ?w.seconds,
    });
    _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    final today = S.life.today;
    final cs = Theme.of(context).colorScheme;
    final programs = S.life.store.ofKind(Kinds.program).where((p) => ((p['days'] as List?) ?? const []).contains(today.weekday)).toList();
    final all = _workouts();
    final todays = all.where((w) => w['date'] == ymd(today)).toList();
    Entity? lastOf(String ex) => all.where((w) => (w['exercise'] as String).toLowerCase() == ex.toLowerCase() && w['date'] != ymd(today)).firstOrNull;
    final best = <String, double>{};
    for (final w in all) {
      final wt = (w['weight'] as num?)?.toDouble();
      if (wt != null && wt > (best[w['exercise']] ?? 0)) best[w['exercise'] as String] = wt;
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _c,
            decoration: const InputDecoration(hintText: 'жим 60 на 10', labelText: 'Записать подход', border: OutlineInputBorder()),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
      ]),
      for (final p in programs) ...[
        SectionTitle('Сегодня по программе: ${p['title']}', padding: const EdgeInsets.fromLTRB(0, 20, 0, 6)),
        for (final ex in ((p['exercises'] as List?) ?? const []).whereType<Map>())
          Builder(builder: (context) {
            final done = todays.where((w) => (w['exercise'] as String).toLowerCase() == '${ex['name']}'.toLowerCase()).toList();
            final last = lastOf('${ex['name']}');
            final plan = '${ex['sets'] ?? 3}×${ex['reps'] ?? 10}${ex['weight'] != null ? ' · ${ex['weight']} кг' : ''}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(done.isNotEmpty ? Icons.check_circle : Icons.fitness_center, color: done.isNotEmpty ? const Color(0xFF2E9E6A) : cs.outline),
              title: Text('${ex['name']}'),
              subtitle: Text('план $plan${last != null ? ' · прошлый раз ${_setText(last)}' : ''}${done.isNotEmpty ? ' · сегодня ${done.length} подх.' : ''}'),
              trailing: TextButton(
                onPressed: () {
                  final w = last?['weight'] ?? ex['weight'];
                  _c.text = '${ex['name']} ${w ?? ''}${w != null ? ' на ' : ' '}${ex['reps'] ?? 10}'.toLowerCase();
                },
                child: const Text('Подход'),
              ),
            );
          }),
      ],
      SectionTitle('Сегодня записано · ${todays.length}', padding: const EdgeInsets.fromLTRB(0, 20, 0, 6)),
      if (todays.isEmpty) Text('Пишите подходы здесь или в поле записи на «Сегодня»: «жим 60 на 10».', style: TextStyle(color: cs.onSurfaceVariant)),
      for (final w in todays)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${w['exercise']}  ${_setText(w)}'),
          trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => S.life.store.delete(w.id)),
        ),
      const SizedBox(height: 8),
      const MetricsCard(only: ['train']),
      if (best.isNotEmpty) ...[
        const SectionTitle('Рекорды', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
        for (final e in best.entries) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Text('🏆'), title: Text(e.key), trailing: Text('${e.value} кг')),
      ],
      if (all.length > todays.length) ...[
        const SectionTitle('Журнал', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
        for (final w in all.where((w) => w['date'] != ymd(today)).take(40))
          ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${w['exercise']}  ${_setText(w)}'), subtitle: Text(dayLabel(parseYmd(w['date'] as String)!))),
      ],
    ]);
  }
}

class _Programs extends StatelessWidget {
  const _Programs();

  @override
  Widget build(BuildContext context) {
    final ps = S.life.store.ofKind(Kinds.program).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Программа — список упражнений по дням недели. В эти дни она появится на вкладке «Сегодня» с прошлым весом.'),
      const SizedBox(height: 8),
      for (final p in ps)
        Card(
          child: ListTile(
            title: Text('${p['title']}'),
            subtitle: Text('${((p['days'] as List?) ?? const []).map((d) => weekdaysShort[(d as num).toInt() - 1]).join(', ')} · '
                '${((p['exercises'] as List?) ?? const []).length} упражнений'),
            onTap: () => _edit(context, p),
          ),
        ),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('Программа'))),
    ]);
  }

  Future<void> _edit(BuildContext context, Entity? p) async {
    final title = TextEditingController(text: p?['title'] as String? ?? '');
    final days = <int>{...((p?['days'] as List?) ?? const []).map((x) => (x as num).toInt())};
    final ex = TextEditingController(
      text: ((p?['exercises'] as List?) ?? const []).whereType<Map>().map((e) => '${e['name']} ${e['sets'] ?? 3}x${e['reps'] ?? 10}${e['weight'] != null ? ' ${e['weight']}' : ''}').join('\n'),
    );
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(p == null ? 'Новая программа' : 'Программа'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Название', hintText: 'Верх / Низ / Фулбоди')),
                const SizedBox(height: 8),
                Wrap(spacing: 4, children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(label: Text(weekdaysShort[i - 1]), selected: days.contains(i), onSelected: (v) => setState(() => v ? days.add(i) : days.remove(i))),
                ]),
                TextField(
                  controller: ex,
                  maxLines: 8,
                  minLines: 4,
                  decoration: const InputDecoration(labelText: 'Упражнения, по одному в строке', hintText: 'Жим лёжа 3x10 60\nПодтягивания 3x8'),
                ),
              ]),
            ),
          ),
          actions: [
            if (p != null) TextButton(onPressed: () {
              S.life.store.delete(p.id);
              Navigator.pop(context);
            }, child: const Text('Удалить')),
            FilledButton(
              onPressed: () {
                final list = [
                  for (final line in ex.text.split('\n').where((l) => l.trim().isNotEmpty))
                    () {
                      final m = RegExp(r'^(.*?)\s+(\d+)\s*[xх×]\s*(\d+)(?:\s+(\d+(?:[.,]\d+)?))?\s*$').firstMatch(line.trim());
                      return m == null
                          ? {'name': line.trim()}
                          : {'name': m[1]!.trim(), 'sets': int.parse(m[2]!), 'reps': int.parse(m[3]!), if (m[4] != null) 'weight': double.parse(m[4]!.replaceAll(',', '.'))};
                    }(),
                ];
                final f = {'title': title.text.trim().isEmpty ? 'Тренировка' : title.text.trim(), 'days': days.toList()..sort(), 'exercises': list};
                if (p == null) {
                  S.life.store.create(Kinds.program, f);
                } else {
                  S.life.store.patch(p.id, f);
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

class _Food extends StatefulWidget {
  const _Food();
  @override
  State<_Food> createState() => _FoodState();
}

class _FoodState extends State<_Food> {
  final _c = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final today = ymd(S.life.today);
    final meals = S.life.store.ofKind(Kinds.meal).where((m) => m['date'] == today).toList()
      ..sort((a, b) => ((a['time'] as String?) ?? '').compareTo((b['time'] as String?) ?? ''));
    final protein = meals.fold(0.0, (a, m) => a + ((m['protein'] as num?)?.toDouble() ?? 0));
    final kcal = meals.fold(0.0, (a, m) => a + ((m['kcal'] as num?)?.toDouble() ?? 0));
    final goal = S.life.store.get('nutrition');
    final pt = (goal?['protein'] as num?) ?? 120, kt = (goal?['kcal'] as num?) ?? 2500;
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const MetricsCard(only: ['water']),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text('Белок ${protein.round()} / $pt г')),
        Expanded(child: BlockBar(value: protein / pt, height: 8)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: Text('Калории ${kcal.round()} / $kt')),
        Expanded(child: BlockBar(value: kcal / kt, height: 8, color: cs.tertiary)),
      ]),
      TextButton(onPressed: () => _targets(context), child: const Text('Изменить цели по белку и калориям')),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _c,
            decoration: const InputDecoration(labelText: 'Что съели', hintText: 'овсянка 350 ккал 12 г белка', border: OutlineInputBorder()),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: 8),
      for (final m in meals)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text('${m['time'] ?? ''}'),
          title: Text('${m['text']}'),
          subtitle: Text([if (m['kcal'] != null) '${m['kcal']} ккал', if (m['protein'] != null) '${m['protein']} г белка'].join(' · ')),
          trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => S.life.store.delete(m.id)),
        ),
    ]);
  }

  void _add() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    final kcal = RegExp(r'(\d+)\s*ккал').firstMatch(t)?[1];
    final prot = RegExp(r'(\d+)\s*г(?:р)?\s*бел').firstMatch(t)?[1];
    final now = DateTime.now();
    S.life.store.create(Kinds.meal, {
      'date': ymd(now),
      'time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'text': t.replaceAll(RegExp(r'\d+\s*ккал|\d+\s*г(?:р)?\s*белка?'), '').trim(),
      if (kcal != null) 'kcal': int.parse(kcal),
      if (prot != null) 'protein': int.parse(prot),
    });
    _c.clear();
  }

  Future<void> _targets(BuildContext context) async {
    final g = S.life.store.get('nutrition');
    final p = TextEditingController(text: '${g?['protein'] ?? 120}');
    final k = TextEditingController(text: '${g?['kcal'] ?? 2500}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Цели питания'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Белок, г в день')),
          TextField(controller: k, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Калории в день')),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить'))],
      ),
    );
    if (ok == true) S.life.store.update('nutrition', 'nutrition', {'protein': int.tryParse(p.text) ?? 120, 'kcal': int.tryParse(k.text) ?? 2500});
  }
}
