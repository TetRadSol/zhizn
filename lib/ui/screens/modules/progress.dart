import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../logic/motivation.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';

/// Уровень и опыт — маленькая плашка на «Сегодня».
class LevelChip extends StatelessWidget {
  const LevelChip({super.key});
  @override
  Widget build(BuildContext context) {
    final l = Motivation(S.life.store, S.life.today).level;
    return Tooltip(
      message: 'Уровень и опыт. Нажмите — награды и статистика',
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: const Text('⭐'),
        label: Text('${l.level} · ${l.name}'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgressScreen())),
      ),
    );
  }
}

/// Мотивация и статистика: уровень, единая шкала, серии, идеальные дни, награды, графики.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Прогресс'), bottom: const TabBar(tabs: [Tab(text: 'Награды'), Tab(text: 'Статистика')])),
        body: ListenableBuilder(
          listenable: S.life,
          builder: (context, _) {
            final m = Motivation(S.life.store, S.life.today);
            return TabBarView(children: [_Rewards(m: m), _Stats(m: m)]);
          },
        ),
      ),
    );
  }
}

class _Rewards extends StatelessWidget {
  const _Rewards({required this.m});
  final Motivation m;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = m.level;
    final sc = m.scale;
    final rewards = S.life.store.ofKind(Kinds.reward).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Уровень ${l.level} · ${l.name}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            BlockBar(value: (l.xp - l.from) / (l.to - l.from), blocks: 20, height: 10),
            const SizedBox(height: 6),
            Text('${l.xp} опыта · до следующего уровня ${l.to - l.xp}', style: TextStyle(color: cs.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text('Опыт: дело +10 (🔴 +20), привычка ✓ +5, пара ✓ +3, идеальный день ⭐ +30, недельный обзор +20.',
                style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🌿 Единая шкала', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(sc.total * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
            ]),
            const SizedBox(height: 6),
            BlockBar(value: sc.total, blocks: 20),
            const SizedBox(height: 6),
            Text(
              'привычки ${(sc.habits * 100).round()}% · дела ${sc.tasks == null ? '—' : '${(sc.tasks! * 100).round()}%'} · '
              'пары ${sc.lessons == null ? '—' : '${(sc.lessons! * 100).round()}%'} · цели ${sc.goals == null ? '—' : '${(sc.goals! * 100).round()}%'}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _Stat('🔥', '${m.bestStreak}', 'рекорд серии'),
        _Stat('⭐', '${m.idealDays}', 'идеальных дней'),
        _Stat('✓', '${m.totalChecks}', 'отметок'),
        _Stat('✅', '${m.tasksDone}', 'дел сделано'),
      ]),
      SectionTitle(
        'Награды',
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 6),
        trailing: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Награда'), onPressed: () => _edit(context, null)),
      ),
      if (rewards.isEmpty) const Text('Добавьте награду: что подарите себе и за что.'),
      for (final r in rewards)
        Builder(builder: (context) {
          final th = (r['threshold'] as num?) ?? 1;
          final v = m.value(r['cond'] as String? ?? '');
          final p = (v / th).clamp(0, 1).toDouble();
          final open = p >= 1;
          final got = r['claimed'] == true;
          return Card(
            child: ListTile(
              onLongPress: () => _edit(context, r.id),
              leading: Text(got ? '✅' : (open ? '🎁' : '🔒'), style: const TextStyle(fontSize: 24)),
              title: Text('${r['title']}'),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${Motivation.conditions[r['cond']] ?? r['cond']}: ${v is double ? v.toStringAsFixed(0) : v} из $th'),
                const SizedBox(height: 4),
                BlockBar(value: p, height: 6),
              ]),
              trailing: open && !got
                  ? FilledButton(onPressed: () => S.life.store.patch(r.id, {'claimed': true}), child: const Text('Забрать'))
                  : null,
            ),
          );
        }),
      const SizedBox(height: 8),
      Text('Долгое нажатие на награду — изменить.', style: TextStyle(color: cs.outline, fontSize: 12)),
    ]);
  }

  Future<void> _edit(BuildContext context, String? id) async {
    final r = id == null ? null : S.life.store.get(id);
    final title = TextEditingController(text: r?['title'] as String? ?? '');
    final th = TextEditingController(text: '${r?['threshold'] ?? ''}');
    var cond = (r?['cond'] as String?) ?? 'streak';
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(r == null ? 'Новая награда' : 'Награда'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Что подарю себе')),
            DropdownButtonFormField<String>(
              initialValue: cond,
              decoration: const InputDecoration(labelText: 'Условие'),
              items: [for (final e in Motivation.conditions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => cond = v!),
            ),
            TextField(controller: th, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Порог')),
          ]),
          actions: [
            if (r != null)
              TextButton(
                onPressed: () {
                  S.life.store.delete(r.id);
                  Navigator.pop(context);
                },
                child: const Text('Удалить'),
              ),
            FilledButton(
              onPressed: () {
                final f = {'title': title.text.trim(), 'cond': cond, 'threshold': num.tryParse(th.text.replaceAll(',', '.')) ?? 1};
                if (r == null) {
                  S.life.store.create(Kinds.reward, f);
                } else {
                  S.life.store.patch(r.id, f);
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

class _Stat extends StatelessWidget {
  const _Stat(this.emoji, this.value, this.label);
  final String emoji, value, label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    ),
  );
}

/// Простая столбчатая диаграмма.
class Bars extends StatelessWidget {
  const Bars({super.key, required this.values, required this.labels, this.height = 120, this.color});
  final List<double> values;
  final List<String> labels;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mx = values.fold(0.0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: height + 34,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (values[i] > 0) Text(values[i] == values[i].roundToDouble() ? '${values[i].toInt()}' : values[i].toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
              Container(
                height: mx == 0 ? 2 : (values[i] / mx * height).clamp(2, height),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: color ?? cs.primary, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(height: 2),
              Text(labels[i], style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ]),
          ),
      ]),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.m});
  final Motivation m;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = S.life.today;
    final days = List.generate(14, (i) => today.subtract(Duration(days: 13 - i)));
    final tasks = S.life.tasks;
    final done = [
      for (final d in days)
        tasks.where((t) => t.completedOn(d) || (t.done && t.doneAt != null && dayOf(t.doneAt!) == d)).length.toDouble(),
    ];
    final habitPct = [
      for (final d in days)
        () {
          final hs = S.life.habits.where((h) => h.activeOn(d) && h.mark(d) != null && h.mark(d) != '–').toList();
          return hs.isEmpty ? 0.0 : (hs.where((h) => h.mark(d) == '✓').length / hs.length * 100).roundToDouble();
        }(),
    ];
    final metrics = [for (final d in days) S.life.store.get('metrics:${ymd(d)}')];
    double? avg(String k) {
      final v = metrics.map((e) => (e?[k] as num?)?.toDouble()).whereType<double>().toList();
      return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    }

    final bySphere = <String, List<double>>{};
    for (final h in S.life.habits) {
      bySphere.putIfAbsent(h.sphere ?? 'other', () => []).add(h.percent(today));
    }
    final labels = [for (final d in days) '${d.day}'];
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Сделано дел за 14 дней', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Bars(values: done, labels: labels),
      const SizedBox(height: 16),
      const Text('Привычки, % выполнения по дням', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Bars(values: habitPct, labels: labels, color: const Color(0xFF2E9E6A)),
      const SizedBox(height: 16),
      const Text('Привычки по сферам (30 дней)', style: TextStyle(fontWeight: FontWeight.w700)),
      for (final e in bySphere.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 170, child: Text(Sphere.byId(e.key)?.label ?? 'Другое')),
            Expanded(child: BlockBar(value: e.value.reduce((a, b) => a + b) / e.value.length, height: 8)),
            SizedBox(width: 44, child: Text(' ${(e.value.reduce((a, b) => a + b) / e.value.length * 100).round()}%')),
          ]),
        ),
      const SizedBox(height: 16),
      const Text('Средние показатели за 14 дней', style: TextStyle(fontWeight: FontWeight.w700)),
      for (final mt in Metric.all)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text(mt.emoji, style: const TextStyle(fontSize: 20)),
          title: Text(mt.name),
          trailing: Text(
            avg(mt.id) == null ? '—' : '${avg(mt.id)!.toStringAsFixed(mt.step < 1 ? 1 : 0)} / цель ${mt.max ? '≤' : '≥'} ${mt.target}',
            style: TextStyle(color: avg(mt.id) == null ? cs.outline : (mt.ok(avg(mt.id)!) ? const Color(0xFF2E9E6A) : cs.error)),
          ),
        ),
    ]);
  }
}
