import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../logic/motivation.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';
import '../task_editor.dart';

// ---------- Покупки ----------

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});
  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final _c = TextEditingController();

  void _add() {
    for (final line in _c.text.split(RegExp(r'[,;\n]'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      S.life.store.create(Kinds.task, {'title': t[0].toUpperCase() + t.substring(1), 'type': 'shopping', 'sphere': 'home'});
    }
    _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Список покупок')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final items = S.life.tasks.where((t) => t.type == 'shopping').toList();
          final open = items.where((t) => !t.done).toList();
          final done = items.where((t) => t.done && t.doneAt != null && t.doneAt!.isAfter(DateTime.now().subtract(const Duration(days: 3)))).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  decoration: const InputDecoration(hintText: 'молоко, хлеб, порошок', border: OutlineInputBorder()),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
            ]),
            const SizedBox(height: 4),
            Text('Можно и в поле записи: «купить молоко».', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            if (open.isEmpty) const EmptyHint(icon: Icons.shopping_cart_outlined, title: 'Список пуст'),
            for (final t in open)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: false,
                title: Text(t.title),
                onChanged: (_) => S.life.complete(t),
              ),
            if (done.isNotEmpty) ...[
              const SectionTitle('Куплено', padding: EdgeInsets.fromLTRB(0, 16, 0, 4)),
              for (final t in done)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: true,
                  title: Text(t.title, style: const TextStyle(decoration: TextDecoration.lineThrough)),
                  onChanged: (_) => S.life.uncomplete(t),
                ),
            ],
          ]);
        },
      ),
    );
  }
}

// ---------- Недельный обзор ----------

DateTime mondayOf(DateTime d) => dayOf(d).subtract(Duration(days: d.weekday - 1));

class WeekReviewScreen extends StatefulWidget {
  const WeekReviewScreen({super.key, this.monday});
  final DateTime? monday;
  @override
  State<WeekReviewScreen> createState() => _WeekReviewScreenState();
}

class _WeekReviewScreenState extends State<WeekReviewScreen> {
  late DateTime _mon = widget.monday ?? mondayOf(S.life.today);
  late final Map<String, TextEditingController> _c = {for (final k in ['win', 'improve', 'focus']) k: TextEditingController()};
  int? _score;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final e = S.life.store.get('week:${ymd(_mon)}');
    for (final k in _c.keys) {
      _c[k]!.text = (e?[k] as String?) ?? '';
    }
    _score = (e?['score'] as num?)?.toInt();
  }

  void _save() {
    S.life.store.update('week:${ymd(_mon)}', Kinds.week, {
      'score': _score,
      for (final k in _c.keys) k: _c[k]!.text.trim(),
    });
    toast(context, 'Обзор недели сохранён (+20 опыта)');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = List.generate(7, (i) => _mon.add(Duration(days: i)));
    final m = Motivation(S.life.store, S.life.today);
    final done = S.life.tasks.where((t) => days.any((d) => t.completedOn(d) || (t.done && t.doneAt != null && dayOf(t.doneAt!) == d))).length;
    final ideal = days.where(m.ideal).length;
    final moods = days.map((d) => (S.life.store.get('metrics:${ymd(d)}')?['mood'] as num?)?.toDouble()).whereType<double>().toList();
    var ok = 0, all = 0;
    for (final h in S.life.habits) {
      for (final d in days) {
        final mk = h.mark(d);
        if (mk == '✓') ok++;
        if (mk == '✓' || mk == '✗') all++;
      }
    }
    final past = S.life.store.ofKind(Kinds.week).toList()..sort((a, b) => b.id.compareTo(a.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Недельный обзор')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          IconButton(onPressed: () => setState(() {
            _mon = _mon.subtract(const Duration(days: 7));
            _load();
          }), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${_mon.day}.${_mon.month} – ${days.last.day}.${days.last.month}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(onPressed: () => setState(() {
            _mon = _mon.add(const Duration(days: 7));
            _load();
          }), icon: const Icon(Icons.chevron_right)),
        ]),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 16, runSpacing: 8, children: [
              Text('Привычки: ${all == 0 ? '—' : '${(ok / all * 100).round()}%'}'),
              Text('Идеальных дней ⭐: $ideal'),
              Text('Сделано дел: $done'),
              Text('Настроение: ${moods.isEmpty ? '—' : (moods.reduce((a, b) => a + b) / moods.length).toStringAsFixed(1)}'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Оценка недели'),
        Wrap(spacing: 4, children: [
          for (var i = 1; i <= 10; i++) ChoiceChip(label: Text('$i'), selected: _score == i, onSelected: (_) => setState(() => _score = i)),
        ]),
        const SizedBox(height: 12),
        for (final (k, label) in const [('win', '🏆 Главная победа'), ('improve', '🔧 Что улучшить'), ('focus', '🎯 Фокус на следующую неделю')])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(controller: _c[k], maxLines: 3, minLines: 1, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
          ),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
        if (past.length > 1) ...[
          const SectionTitle('Прошлые недели', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
          for (final w in past.where((w) => w.id != 'week:${ymd(_mon)}').take(10))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Неделя с ${dayLabel(parseYmd(w.id.substring(5))!)} · ${w['score'] ?? '—'}/10'),
              subtitle: Text([if ('${w['win'] ?? ''}'.isNotEmpty) '🏆 ${w['win']}', if ('${w['focus'] ?? ''}'.isNotEmpty) '🎯 ${w['focus']}'].join('\n'), style: TextStyle(color: cs.onSurfaceVariant)),
            ),
        ],
      ]),
    );
  }
}

// ---------- Матрица «важно / срочно» ----------

bool isUrgent(Task t, DateTime today) => t.due != null && !t.due!.isAfter(today.add(const Duration(days: 2)));
bool isImportant(Task t) => t.prio == Prio.red || t.prio == Prio.yellow || t.type == 'deadline' || t.type == 'hw';

class MatrixScreen extends StatelessWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Важно / срочно')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final today = S.life.today;
          final open = S.life.tasks.where((t) => !t.done && t.type != 'shopping').toList()..sort((a, b) => a.due == null ? 1 : (b.due == null ? -1 : a.due!.compareTo(b.due!)));
          List<Task> q(bool imp, bool urg) => open.where((t) => isImportant(t) == imp && isUrgent(t, today) == urg).toList();
          final cs = Theme.of(context).colorScheme;
          Widget box(String title, String hint, List<Task> list, Color color) => Card(
            color: color.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$title · ${list.length}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                Text(hint, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                const Divider(),
                for (final t in list.take(12))
                  InkWell(
                    onTap: () => openTaskEditor(context, t.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('${Prio.emoji(t.prio)} ${t.title}${t.due != null ? ' · ${dayLabel(t.due!)}' : ''}'.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                if (list.length > 12) Text('и ещё ${list.length - 12}', style: TextStyle(color: cs.outline)),
              ]),
            ),
          );
          final boxes = [
            box('Сделать сейчас', 'важно и срочно', q(true, true), cs.error),
            box('Запланировать', 'важно, не срочно', q(true, false), cs.primary),
            box('Быстро разделаться', 'срочно, не очень важно', q(false, true), cs.tertiary),
            box('Когда будет время', 'не важно и не срочно', q(false, false), cs.outline),
          ];
          return ListView(padding: const EdgeInsets.all(8), children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Строится сама: важность — 🔴🟡, сдачи и ДЗ; срочность — срок в ближайшие 2 дня.', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            if (isNarrow(context)) ...boxes else ...[
              IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: boxes[0]), Expanded(child: boxes[1])])),
              IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: boxes[2]), Expanded(child: boxes[3])])),
            ],
          ]);
        },
      ),
    );
  }
}

// ---------- План недели (удобнее на ноутбуке) ----------

class WeekPlanScreen extends StatefulWidget {
  const WeekPlanScreen({super.key});
  @override
  State<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends State<WeekPlanScreen> {
  late DateTime _mon = mondayOf(S.life.today);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('План недели'),
        actions: [
          IconButton(onPressed: () => setState(() => _mon = _mon.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_left)),
          TextButton(onPressed: () => setState(() => _mon = mondayOf(S.life.today)), child: const Text('Эта неделя')),
          IconButton(onPressed: () => setState(() => _mon = _mon.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_right)),
        ],
      ),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final today = S.life.today;
          final days = List.generate(7, (i) => _mon.add(Duration(days: i)));
          final open = S.life.tasks.where((t) => !t.done && t.type != 'shopping').toList();
          final noDate = open.where((t) => t.due == null).toList();
          final overdue = open.where((t) => t.due != null && t.due!.isBefore(today)).toList();
          final busy = S.life.busy;

          Widget column(String title, String? sub, List<Task> tasks, DateTime? day, {bool highlight = false, String? busyTitle}) {
            return DragTarget<Task>(
              onAcceptWithDetails: (d) => S.life.moveTo(d.data, day),
              builder: (context, cand, _) => Container(
                width: 190,
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cand.isNotEmpty ? cs.primaryContainer : (highlight ? cs.secondaryContainer.withValues(alpha: 0.5) : cs.surfaceContainerLow),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  if (busyTitle != null) Text('⚡ $busyTitle', style: TextStyle(color: cs.error, fontSize: 12)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(children: [
                      for (final t in tasks)
                        Draggable<Task>(
                          data: t,
                          feedback: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(width: 180, padding: const EdgeInsets.all(8), child: Text(t.title)),
                          ),
                          childWhenDragging: Opacity(opacity: 0.3, child: _chip(t, cs)),
                          child: InkWell(onTap: () => openTaskEditor(context, t.id), child: _chip(t, cs)),
                        ),
                    ]),
                  ),
                ]),
              ),
            );
          }

          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Перетаскивайте дела мышкой между днями. Нажмите на дело, чтобы изменить.', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            Expanded(
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(4), children: [
                if (overdue.isNotEmpty) column('Просрочено', null, overdue, today),
                for (final d in days)
                  column(
                    '${weekdaysShort[d.weekday - 1]}, ${d.day}.${d.month.toString().padLeft(2, '0')}',
                    () {
                      final l = S.life.schedule.on(d);
                      return l.isEmpty ? 'пар нет' : '${l.length} пар до ${l.last.end}';
                    }(),
                    open.where((t) => t.due == d).toList()..sort(_byTime),
                    d,
                    highlight: d == today,
                    busyTitle: busy.where((b) => !b.from.isAfter(d) && !b.to.isBefore(d)).firstOrNull?.title,
                  ),
                column('Без срока', null, noDate, null),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _chip(Task t, ColorScheme cs) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outlineVariant)),
    child: Text('${t.time != null ? '${t.time} ' : ''}${Prio.emoji(t.prio)} ${t.title}'.trim(), style: const TextStyle(fontSize: 13)),
  );
}

int _byTime(Task a, Task b) {
  final at = a.time, bt = b.time;
  if (at != null && bt != null) return at.compareTo(bt);
  if ((at == null) != (bt == null)) return at == null ? 1 : -1;
  return Prio.rank(a.prio).compareTo(Prio.rank(b.prio));
}

