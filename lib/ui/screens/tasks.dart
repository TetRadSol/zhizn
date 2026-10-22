import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/life.dart';
import '../../services/services.dart';
import '../widgets/common.dart';
import '../widgets/task_tile.dart';
import 'more.dart';
import 'task_editor.dart';

/// Все дела списком: просрочено, сегодня, завтра, неделя, позже, без срока.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String? _sphere;
  String _query = '';
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTaskEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Дело'),
      ),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final today = dayOf(DateTime.now());
          final q = _query.toLowerCase();
          var all = S.life.tasks.where((t) {
            if (_sphere != null && t.sphere != _sphere) return false;
            if (q.isNotEmpty && !'${t.title} ${t.notes}'.toLowerCase().contains(q)) return false;
            return true;
          }).toList()
            ..sort(Life.compareTasks);
          final open = all.where((t) => !t.done).toList();
          final done = all.where((t) => t.done).toList()
            ..sort((a, b) => (b.doneAt ?? DateTime(2000)).compareTo(a.doneAt ?? DateTime(2000)));

          final groups = <String, List<Task>>{
            'Просрочено': [],
            'Сегодня': [],
            'Завтра': [],
            'На этой неделе': [],
            'Позже': [],
            'Без срока': [],
          };
          final weekEnd = today.add(Duration(days: 7 - today.weekday));
          for (final t in open) {
            final d = t.due;
            final key = d == null
                ? 'Без срока'
                : d.isBefore(today)
                ? 'Просрочено'
                : d == today
                ? 'Сегодня'
                : d == today.add(const Duration(days: 1))
                ? 'Завтра'
                : !d.isAfter(weekEnd)
                ? 'На этой неделе'
                : 'Позже';
            groups[key]!.add(t);
          }
          final goals = S.life.goals.where((g) => _sphere == null || g['sphere'] == _sphere).toList();

          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Дела', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Поиск по делам',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(children: [
                  ChoiceChip(label: const Text('Все'), selected: _sphere == null, onSelected: (_) => setState(() => _sphere = null)),
                  for (final s in Sphere.all)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: _sphere == s.id,
                        onSelected: (v) => setState(() => _sphere = v ? s.id : null),
                      ),
                    ),
                ]),
              ),
            ),
            if (open.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyHint(
                  icon: Icons.inbox_outlined,
                  title: 'Дел нет',
                  text: 'Добавьте кнопкой «Дело» или напишите на экране «Сегодня»',
                ),
              ),
            for (final g in groups.entries)
              if (g.value.isNotEmpty) ...[
                SliverToBoxAdapter(child: SectionTitle('${g.key} · ${g.value.length}')),
                SliverList.builder(
                  itemCount: g.value.length,
                  itemBuilder: (_, i) => TaskTile(g.value[i], showDate: g.key != 'Сегодня' && g.key != 'Завтра'),
                ),
              ],
            if (goals.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionTitle('Цели')),
              SliverList.builder(
                itemCount: goals.length,
                itemBuilder: (_, i) {
                  final g = goals[i];
                  return ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    onTap: () => openEntityEditor(context, g.id),
                    title: Text(g['title'] as String? ?? ''),
                    subtitle: Text(
                      [
                        Sphere.byId(g['sphere'] as String?)?.label ?? '',
                        if (g['measure'] != null) 'измеряем: ${g['measure']}${g['target'] != null ? ', цель ${g['target']}' : ''}',
                        if (g['due'] != null) 'до ${dayLabel(parseYmd(g['due'] as String)!)}',
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                  );
                },
              ),
            ],
            if (done.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    icon: Icon(_showDone ? Icons.expand_less : Icons.expand_more),
                    label: Text(_showDone ? 'Скрыть сделанные' : 'Показать сделанные (${done.length})'),
                    onPressed: () => setState(() => _showDone = !_showDone),
                  ),
                ),
              ),
            if (_showDone) SliverList.builder(itemCount: done.length, itemBuilder: (_, i) => TaskTile(done[i], dense: true)),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ]);
        },
      ),
    );
  }
}
