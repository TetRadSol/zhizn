import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../data/store.dart';
import '../../../logic/motivation.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';

const goalSources = {
  null: 'Вручную',
  'exams': 'Сдано зачётов и экзаменов',
  'driving': 'Занятий вождения',
  'savings': 'Накоплено, Br',
  'weight': 'Вес из раздела «Здоровье»',
  'study_hours': 'Часы учёбы из показателей дня',
};

/// Цели: цель → этапы → шаги, прогресс считается сам.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Цели')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openGoal(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Цель'),
      ),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final goals = S.life.goals.where((g) => g['archived'] != true).toList()
            ..sort((a, b) => ((a['due'] as String?) ?? '9').compareTo((b['due'] as String?) ?? '9'));
          final mot = Motivation(S.life.store, S.life.today);
          if (goals.isEmpty) {
            return const EmptyHint(icon: Icons.flag_outlined, title: 'Целей пока нет', text: 'Добавьте цель или напишите «цель: получить права»');
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            for (final g in goals) _GoalCard(g: g, mot: mot),
          ]);
        },
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.g, required this.mot});
  final Entity g;
  final Motivation mot;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = mot.goal(g);
    final stages = ((g['stages'] as List?) ?? const []).whereType<Map>().toList();
    final due = parseYmd(g['due'] as String?);
    final left = due?.difference(S.life.today).inDays;
    final linked = S.life.tasks.where((t) => t.e['goal'] == g.id && !t.done).length;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openGoal(context, g.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(Sphere.byId(g['sphere'] as String?)?.emoji ?? '🎯', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(child: Text('${g['title']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              Text('${(p.progress * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
            ]),
            const SizedBox(height: 8),
            BlockBar(value: p.progress, height: 10),
            const SizedBox(height: 6),
            Text(
              [
                if (g['measure'] != null) '${g['measure']}: ${_fmt(p.current) ?? '—'}${g['target'] != null ? ' из ${g['target']}' : ''}',
                if (stages.isNotEmpty) 'этапы ${stages.where((s) => s['d'] == true).length}/${stages.length}',
                if (left != null) left >= 0 ? 'осталось $left дн.' : 'срок прошёл',
                if (linked > 0) 'дел: $linked',
              ].join(' · '),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ]),
        ),
      ),
    );
  }
}

String? _fmt(num? v) => v == null ? null : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));

Future<void> openGoal(BuildContext context, String? id) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => GoalEditor(id: id)));

class GoalEditor extends StatefulWidget {
  const GoalEditor({super.key, this.id});
  final String? id;
  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  late final Entity? _g = widget.id == null ? null : S.life.store.get(widget.id!);
  late final _title = TextEditingController(text: _g?['title'] as String? ?? '');
  late final _measure = TextEditingController(text: _g?['measure'] as String? ?? '');
  late final _start = TextEditingController(text: '${_g?['start'] ?? ''}');
  late final _target = TextEditingController(text: '${_g?['target'] ?? ''}');
  late final _current = TextEditingController(text: '${_g?['current'] ?? ''}');
  late String? _sphere = _g?['sphere'] as String?;
  late String? _source = _g?['source'] as String?;
  late DateTime? _due = parseYmd(_g?['due'] as String?);
  late final List<Map<String, dynamic>> _stages = [
    for (final s in ((_g?['stages'] as List?) ?? const []).whereType<Map>())
      {'t': s['t'], 'd': s['d'] == true, 'steps': [for (final x in ((s['steps'] as List?) ?? const []).whereType<Map>()) {'t': x['t'], 'd': x['d'] == true}]},
  ];

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final f = {
      'title': _title.text.trim(),
      'sphere': _sphere,
      'measure': _measure.text.trim().isEmpty ? null : _measure.text.trim(),
      'start': _start.text.trim().isEmpty ? null : _start.text.trim(),
      'target': _target.text.trim().isEmpty ? null : _target.text.trim(),
      'current': num.tryParse(_current.text.trim().replaceAll(',', '.')),
      'source': _source,
      'due': _due == null ? null : ymd(_due!),
      'stages': _stages,
    };
    if (_g == null) {
      S.life.store.create(Kinds.goal, f);
    } else {
      S.life.store.patch(_g.id, f);
    }
    Navigator.pop(context);
  }

  Future<String?> _ask(String title, [String text = '']) async {
    final c = TextEditingController(text: text);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Готово'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tasks = _g == null ? const <Task>[] : S.life.tasks.where((t) => t.e['goal'] == _g.id).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_g == null ? 'Новая цель' : 'Цель'),
        actions: [
          if (_g != null)
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                S.life.store.delete(_g.id);
                Navigator.pop(context);
                toast(context, 'Цель удалена', action: 'Вернуть', onAction: () => S.life.store.restore(_g.id));
              },
            ),
          TextButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Цель', border: OutlineInputBorder()), textCapitalization: TextCapitalization.sentences),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in Sphere.all)
            ChoiceChip(label: Text(s.label), selected: _sphere == s.id, onSelected: (v) => setState(() => _sphere = v ? s.id : null)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          const Text('Срок: '),
          TextButton(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _due ?? S.life.today, firstDate: DateTime(2020), lastDate: DateTime(2035));
              if (d != null) setState(() => _due = d);
            },
            child: Text(_due == null ? 'без срока' : dayLabel(_due!)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Как измеряем', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(controller: _measure, decoration: const InputDecoration(labelText: 'Что считаем', hintText: 'кг, Br, занятий…', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _source,
          decoration: const InputDecoration(labelText: 'Откуда брать «сейчас»', border: OutlineInputBorder()),
          items: [for (final e in goalSources.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _source = v),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _start, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Старт', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          if (_source == null) ...[
            Expanded(child: TextField(controller: _current, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Сейчас', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
          ],
          Expanded(child: TextField(controller: _target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Цель', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Text('Этапы и шаги', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Этап'),
            onPressed: () async {
              final t = await _ask('Новый этап');
              if (t != null && t.trim().isNotEmpty) setState(() => _stages.add({'t': t.trim(), 'd': false, 'steps': <Map<String, dynamic>>[]}));
            },
          ),
        ]),
        if (_stages.isEmpty) Text('Разбейте цель на этапы, а этапы — на шаги. Или попросите Джарвиса: напишите «Джарвис, разбей цель …».', style: TextStyle(color: cs.onSurfaceVariant)),
        for (final st in _stages)
          Card(
            child: Column(children: [
              CheckboxListTile(
                value: st['d'] == true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${st['t']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                secondary: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'step') {
                      final t = await _ask('Шаг этапа «${st['t']}»');
                      if (t != null && t.trim().isNotEmpty) setState(() => (st['steps'] as List).add({'t': t.trim(), 'd': false}));
                    } else if (v == 'del') {
                      setState(() => _stages.remove(st));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'step', child: Text('Добавить шаг')),
                    PopupMenuItem(value: 'del', child: Text('Удалить этап')),
                  ],
                ),
                onChanged: (v) => setState(() => st['d'] = v == true),
              ),
              for (final step in (st['steps'] as List).cast<Map>())
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: CheckboxListTile(
                    dense: true,
                    value: step['d'] == true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${step['t']}'),
                    onChanged: (v) => setState(() => step['d'] = v == true),
                  ),
                ),
            ]),
          ),
        if (tasks.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Дела по цели', style: Theme.of(context).textTheme.titleSmall),
          for (final t in tasks) ListTile(dense: true, leading: Icon(t.done ? Icons.check_circle : Icons.radio_button_unchecked), title: Text(t.title)),
        ],
      ]),
    );
  }
}
