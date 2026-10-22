import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/services.dart';
import '../widgets/common.dart';

/// Привычки сеткой, как в Excel: ✓ / – / ✗ по дням, процент и серия.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editHabit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Привычка'),
      ),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final habits = S.life.habits;
          final cs = Theme.of(context).colorScheme;
          final today = dayOf(DateTime.now());
          final n = isNarrow(context) ? 7 : 14;
          final days = List.generate(n, (i) => today.subtract(Duration(days: n - 1 - i)));
          // Клетки сжимаются, чтобы названию оставалось не меньше 120 точек
          final width = MediaQuery.sizeOf(context).width - (isNarrow(context) ? 24 : 120);
          final cell = ((width - 120) / n - 4).clamp(24.0, 36.0);

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Привычки', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Нажмите на клетку: ✓ сделано → – пропуск по причине → ✗ не сделано. Пропуск «–» не обрывает серию.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              if (habits.isEmpty)
                const EmptyHint(
                  icon: Icons.repeat,
                  title: 'Привычек пока нет',
                  text: 'Добавьте кнопкой «Привычка» или напишите «привычка: протеин». '
                      '30 привычек из Excel перенесём, когда пришлёте файл.',
                ),
              if (habits.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                  child: Row(children: [
                    const Expanded(child: SizedBox()),
                    for (final d in days)
                      SizedBox(
                        width: cell + 4,
                        child: Column(children: [
                          Text(weekdaysShort[d.weekday - 1], style: TextStyle(fontSize: 11, color: cs.outline)),
                          Text(
                            '${d.day}',
                            style: TextStyle(fontWeight: d == today ? FontWeight.w800 : FontWeight.w500, color: d == today ? cs.primary : null),
                          ),
                        ]),
                      ),
                  ]),
                ),
              for (final h in habits)
                InkWell(
                  onLongPress: () => editHabit(context, h),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => editHabit(context, h),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Row(children: [
                              SizedBox(
                                width: 42,
                                child: BlockBar(
                                  value: h.percent(today),
                                  blocks: 6,
                                  height: 6,
                                  color: h.percent(today) * 100 >= h.target ? const Color(0xFF2E9E6A) : cs.tertiary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${(h.percent(today) * 100).round()}%${h.streak(today) > 1 ? ' 🔥${h.streak(today)}' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                      for (final d in days)
                        Padding(
                          padding: const EdgeInsets.all(2),
                          child: MarkCell(
                            mark: h.mark(d),
                            size: cell,
                            today: d == today,
                            enabled: h.activeOn(d),
                            onTap: () => S.life.cycleHabit(h, d),
                          ),
                        ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> editHabit(BuildContext context, Habit? h) {
  final title = TextEditingController(text: h?.title ?? '');
  var sphere = h?.sphere;
  var target = h?.target ?? 80;
  final days = <int>{...?h?.days};
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(h == null ? 'Новая привычка' : 'Привычка'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: title,
                autofocus: h == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Название', hintText: 'Например: протеин, 10 000 шагов'),
              ),
              const SizedBox(height: 16),
              const Text('Дни'),
              const SizedBox(height: 6),
              Wrap(spacing: 4, children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(weekdaysShort[i - 1]),
                    selected: days.isEmpty || days.contains(i),
                    onSelected: (v) => setState(() {
                      if (days.isEmpty) days.addAll([1, 2, 3, 4, 5, 6, 7]);
                      v ? days.add(i) : days.remove(i);
                      if (days.length == 7) days.clear();
                    }),
                  ),
              ]),
              const SizedBox(height: 16),
              Text('Цель: $target% дней'),
              Slider(value: target.toDouble(), min: 30, max: 100, divisions: 14, label: '$target%', onChanged: (v) => setState(() => target = v.round())),
              const Text('Сфера'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in Sphere.all)
                  ChoiceChip(label: Text(s.label), selected: sphere == s.id, onSelected: (v) => setState(() => sphere = v ? s.id : null)),
              ]),
            ]),
          ),
        ),
        actions: [
          if (h != null)
            TextButton(
              onPressed: () {
                S.life.store.delete(h.id);
                Navigator.pop(context);
              },
              child: Text('Удалить', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              final f = {'title': title.text.trim(), 'sphere': sphere, 'target': target, 'days': days.toList()..sort()};
              if (h == null) {
                S.life.store.create(Kinds.habit, {...f, 'order': S.life.habits.length});
              } else {
                S.life.store.patch(h.id, f);
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
