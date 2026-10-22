import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';
import 'progress.dart';

/// Показатели дня (сон, вода, шаги…) — кнопками − / +.
class MetricsCard extends StatelessWidget {
  const MetricsCard({super.key, this.day, this.only});
  final DateTime? day;
  final List<String>? only;

  @override
  Widget build(BuildContext context) {
    final d = day ?? S.life.today;
    final id = 'metrics:${ymd(d)}';
    final e = S.life.store.get(id);
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      for (final m in Metric.all.where((m) => only == null || only!.contains(m.id)))
        Builder(builder: (context) {
          final v = (e?[m.id] as num?) ?? 0;
          void set(num nv) => S.life.store.update(id, Kinds.metrics, {m.id: nv < 0 ? 0 : (m.id == 'energy' || m.id == 'mood' ? nv.clamp(0, 5) : nv)});
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Text(m.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(child: Text(m.name)),
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => set(v - m.step), icon: const Icon(Icons.remove_circle_outline)),
              InkWell(
                onTap: () async {
                  final c = TextEditingController(text: '$v');
                  final r = await showDialog<String>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(m.name),
                      content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                      actions: [FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK'))],
                    ),
                  );
                  final n = num.tryParse((r ?? '').replaceAll(',', '.'));
                  if (n != null) set(n);
                },
                child: SizedBox(
                  width: 64,
                  child: Text(
                    v == v.roundToDouble() ? '${v.toInt()}' : '$v',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: v == 0 ? cs.outline : (m.ok(v) ? const Color(0xFF2E9E6A) : null)),
                  ),
                ),
              ),
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => set(v + m.step), icon: const Icon(Icons.add_circle_outline)),
            ]),
          );
        }),
    ]);
  }
}

const defaultSupplements = [
  ('Протеин', ['08:00', '19:00']),
  ('Креатин', ['08:00']),
  ('Витамин D', ['08:00']),
  ('Омега-3', ['13:00']),
  ('Магний', ['22:00']),
  ('Мультивитамины', ['08:00']),
];

/// Здоровье: показатели дня, добавки по расписанию, вес и замеры.
class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Здоровье')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final today = S.life.today;
          final supps = S.life.habits.where((h) => h.e['supp'] == true).toList();
          final body = S.life.store.ofKind(Kinds.body).toList()..sort((a, b) => ((a['date'] as String?) ?? '').compareTo((b['date'] as String?) ?? ''));
          final weights = body.where((b) => b['weight'] != null).toList();
          final cs = Theme.of(context).colorScheme;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const SectionTitle('Показатели сегодня', padding: EdgeInsets.fromLTRB(0, 0, 0, 6)),
            const MetricsCard(),
            SectionTitle(
              'Добавки',
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
              trailing: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Добавка'), onPressed: () => editSupplement(context, null)),
            ),
            if (supps.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () {
                    for (final (t, times) in defaultSupplements) {
                      S.life.store.create(Kinds.habit, {'title': t, 'sphere': 'health', 'supp': true, 'times': times, 'target': 90, 'order': 100 + S.life.habits.length});
                    }
                  },
                  child: const Text('Добавить: протеин, креатин, витамин D, омега-3, магний, мультивитамины'),
                ),
              ),
            for (final h in supps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onLongPress: () => editSupplement(context, h),
                leading: MarkCell(mark: h.mark(today), today: true, onTap: () => S.life.cycleHabit(h, today)),
                title: Text(h.title),
                subtitle: Text('в ${((h.e['times'] as List?) ?? const []).join(', ')} · напомню'),
                trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => editSupplement(context, h)),
              ),
            SectionTitle(
              'Вес и замеры',
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
              trailing: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Записать'), onPressed: () => _addBody(context)),
            ),
            Text('Взвешивайтесь раз в неделю утром натощак — так цифры сравнимы. Можно написать в поле записи: «вес 72,5».',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            if (weights.length >= 2) ...[
              const SizedBox(height: 12),
              Bars(
                values: [for (final w in weights.reversed.take(12).toList().reversed) (w['weight'] as num).toDouble()],
                labels: [for (final w in weights.reversed.take(12).toList().reversed) '${parseYmd(w['date'] as String)!.day}.${parseYmd(w['date'] as String)!.month}'],
                color: cs.tertiary,
              ),
              Text(
                'Изменение: ${((weights.last['weight'] as num) - (weights.first['weight'] as num)).toStringAsFixed(1)} кг с ${dayLabel(parseYmd(weights.first['date'] as String)!)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            for (final b in body.reversed.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text([
                  if (b['weight'] != null) '${b['weight']} кг',
                  if (b['waist'] != null) 'талия ${b['waist']}',
                  if (b['chest'] != null) 'грудь ${b['chest']}',
                  if (b['hips'] != null) 'бёдра ${b['hips']}',
                  if (b['arm'] != null) 'рука ${b['arm']}',
                ].join(' · ')),
                subtitle: Text(dayLabel(parseYmd(b['date'] as String)!)),
                trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => S.life.store.delete(b.id)),
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _addBody(BuildContext context) async {
    final f = {for (final k in ['weight', 'waist', 'chest', 'hips', 'arm']) k: TextEditingController()};
    const names = {'weight': 'Вес, кг', 'waist': 'Талия, см', 'chest': 'Грудь, см', 'hips': 'Бёдра, см', 'arm': 'Рука, см'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Вес и замеры'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in f.entries)
            TextField(controller: e.value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: names[e.key])),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить'))],
      ),
    );
    if (ok != true) return;
    final v = {for (final e in f.entries) if (num.tryParse(e.value.text.replaceAll(',', '.')) != null) e.key: num.parse(e.value.text.replaceAll(',', '.'))};
    if (v.isNotEmpty) S.life.store.create(Kinds.body, {'date': ymd(S.life.today), ...v});
  }
}

Future<void> editSupplement(BuildContext context, Habit? h) async {
  final title = TextEditingController(text: h?.title ?? '');
  final times = TextEditingController(text: ((h?.e['times'] as List?) ?? const ['08:00']).join(', '));
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(h == null ? 'Новая добавка' : 'Добавка'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
        TextField(controller: times, decoration: const InputDecoration(labelText: 'Время приёма', hintText: '08:00, 19:00')),
      ]),
      actions: [
        if (h != null)
          TextButton(
            onPressed: () {
              S.life.store.delete(h.id);
              Navigator.pop(context, false);
            },
            child: const Text('Удалить'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
      ],
    ),
  );
  if (ok != true || title.text.trim().isEmpty) return;
  final t = RegExp(r'(\d{1,2})[:.](\d{2})').allMatches(times.text).map((m) => '${m[1]!.padLeft(2, '0')}:${m[2]}').toList();
  final f = {'title': title.text.trim(), 'times': t, 'supp': true, 'sphere': 'health'};
  if (h == null) {
    S.life.store.create(Kinds.habit, {...f, 'target': 90, 'order': 100 + S.life.habits.length});
  } else {
    S.life.store.patch(h.id, f);
  }
}
