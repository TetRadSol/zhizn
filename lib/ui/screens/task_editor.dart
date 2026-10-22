import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../logic/recurrence.dart';
import '../../services/services.dart';
import '../widgets/common.dart';

/// Открыть задачу. Без id — новая задача.
Future<void> openTaskEditor(BuildContext context, String? id, {DateTime? due}) {
  final child = TaskEditor(id: id, due: due);
  if (isNarrow(context)) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => child,
    );
  }
  return showDialog(
    context: context,
    builder: (_) => Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720), child: child)),
  );
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, this.id, this.due});
  final String? id;
  final DateTime? due;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _RepeatOption {
  const _RepeatOption(this.label, this.make);
  final String label;
  final Map<String, dynamic>? Function(DateTime due) make;
}

final _repeatOptions = [
  _RepeatOption('Не повторять', (_) => null),
  _RepeatOption('Каждый день', (_) => Repeat.daily()),
  _RepeatOption('По будням', (_) => Repeat.weekly([1, 2, 3, 4, 5])),
  _RepeatOption('Каждую неделю', (d) => Repeat.weekly([d.weekday])),
  _RepeatOption('Каждые 2 дня', (_) => Repeat.daily(2)),
  _RepeatOption('Каждые 3 дня', (_) => Repeat.daily(3)),
  _RepeatOption('Раз в месяц', (d) => Repeat.monthly(d.day)),
  _RepeatOption('Раз в год', (_) => Repeat.yearly()),
  _RepeatOption('Через 7 дней после выполнения', (_) => Repeat.afterDone(7)),
];

class _TaskEditorState extends State<TaskEditor> {
  late final Task? _orig = widget.id == null ? null : S.life.task(widget.id!);
  late final _title = TextEditingController(text: _orig?.title ?? '');
  late final _notes = TextEditingController(text: _orig?.notes ?? '');
  late DateTime? _due = _orig?.due ?? widget.due;
  late String? _time = _orig?.time;
  late int? _dur = _orig?.duration;
  late String? _prio = _orig?.prio;
  late String? _sphere = _orig?.sphere;
  late Map<String, dynamic>? _repeat = _orig?.repeat;

  bool get _isNew => _orig == null;

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      toast(context, 'Напишите, что сделать');
      return;
    }
    final fields = <String, dynamic>{
      'title': title,
      'notes': _notes.text.trim(),
      'due': _due == null ? null : ymd(_due!),
      'time': _time,
      'dur': _dur,
      'prio': _prio,
      'sphere': _sphere,
      'repeat': _repeat,
      'draft': false,
    };
    if (_isNew) {
      S.life.store.create(Kinds.task, {...fields, 'type': _time != null ? 'event' : 'task'});
    } else {
      // Пишем только изменённые поля — так история остаётся понятной.
      final changed = {
        for (final e in fields.entries)
          if (!_same(_orig!.e[e.key], e.value)) e.key: e.value,
      };
      if (changed.isNotEmpty) S.life.store.patch(_orig!.id, changed);
    }
    Navigator.pop(context);
  }

  bool _same(dynamic a, dynamic b) {
    if (a is Map && b is Map) return a.toString() == b.toString();
    if ((a == null || a == '') && (b == null || b == '')) return true;
    return a == b;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Срок',
    );
    if (d != null) setState(() => _due = d);
  }

  Future<void> _pickTime() async {
    final p = _time?.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: p == null ? const TimeOfDay(hour: 18, minute: 0) : TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
      helpText: 'Время',
    );
    if (t != null) {
      setState(() {
        _time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        _due ??= dayOf(DateTime.now());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dayOf(DateTime.now());
    final capture = _orig?.captureId == null ? null : S.life.store.get(_orig!.captureId!);
    final repeatIdx = _repeatOptions.indexWhere((o) => Repeat.describe(o.make(_due ?? today)) == Repeat.describe(_repeat));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isNew ? 'Новое дело' : 'Дело', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Что сделать', border: OutlineInputBorder()),
              onSubmitted: (_) => _save(),
            ),
            if (_orig?.draft == true && capture != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Из записи: «${capture['text']}». Разобрано правилами — проверьте поля.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ),
            const _Label('Срок'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('Сегодня'), selected: _due == today, onSelected: (_) => setState(() => _due = today)),
              ChoiceChip(
                label: const Text('Завтра'),
                selected: _due == today.add(const Duration(days: 1)),
                onSelected: (_) => setState(() => _due = today.add(const Duration(days: 1))),
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_month, size: 18),
                label: Text(_due == null || _due == today || _due == today.add(const Duration(days: 1)) ? 'Другая дата' : dayLabel(_due!)),
                onPressed: _pickDate,
              ),
              ChoiceChip(label: const Text('Без срока'), selected: _due == null, onSelected: (_) => setState(() {
                _due = null;
                _time = null;
              })),
            ]),
            const _Label('Время'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(avatar: const Icon(Icons.schedule, size: 18), label: Text(_time ?? 'Без времени'), onPressed: _pickTime),
              if (_time != null) ActionChip(label: const Text('Убрать время'), onPressed: () => setState(() => _time = null)),
              DropdownButton<int?>(
                value: _dur,
                hint: const Text('Сколько займёт'),
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Сколько займёт: не знаю')),
                  for (final m in [10, 15, 30, 45, 60, 90, 120, 180])
                    DropdownMenuItem(value: m, child: Text(m < 60 ? '$m мин' : '${m / 60} ч'.replaceAll('.0', '').replaceAll('.', ','))),
                ],
                onChanged: (v) => setState(() => _dur = v),
              ),
            ]),
            const _Label('Важность'),
            SegmentedButton<String?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Prio.red, label: Text('🔴 Важно')),
                ButtonSegment(value: Prio.yellow, label: Text('🟡 Средне')),
                ButtonSegment(value: Prio.green, label: Text('🟢 Потом')),
                ButtonSegment(value: null, label: Text('Нет')),
              ],
              selected: {_prio},
              onSelectionChanged: (s) => setState(() => _prio = s.first),
            ),
            const _Label('Сфера'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in Sphere.all)
                ChoiceChip(label: Text(s.label), selected: _sphere == s.id, onSelected: (v) => setState(() => _sphere = v ? s.id : null)),
            ]),
            const _Label('Повтор'),
            DropdownButtonFormField<int>(
              initialValue: repeatIdx >= 0 ? repeatIdx : null,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              hint: Text(Repeat.describe(_repeat)),
              items: [for (var i = 0; i < _repeatOptions.length; i++) DropdownMenuItem(value: i, child: Text(_repeatOptions[i].label))],
              onChanged: (i) => setState(() {
                _repeat = _repeatOptions[i!].make(_due ?? today);
                if (_repeat != null) _due ??= today;
              }),
            ),
            const _Label('Заметки'),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Подробности, ссылки, шаги'),
            ),
            const SizedBox(height: 20),
            Row(children: [
              if (!_isNew)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить'),
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  onPressed: () {
                    final id = _orig!.id;
                    S.life.store.delete(id);
                    Navigator.pop(context);
                    toast(context, 'Удалено', action: 'Вернуть', onAction: () => S.life.store.restore(id));
                  },
                ),
              if (!_isNew) TextButton(onPressed: () => _showHistory(context), child: const Text('История')),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Сохранить')),
            ]),
          ],
        ),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    final ops = S.life.store.history(_orig!.id);
    const names = {
      'title': 'название', 'due': 'срок', 'time': 'время', 'done': 'сделано', 'prio': 'важность',
      'sphere': 'сфера', 'repeat': 'повтор', 'notes': 'заметки', 'dur': 'длительность', '_del': 'удалено',
    };
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('История изменений'),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final o in ops.where((o) => names.containsKey(o.field)))
                ListTile(
                  dense: true,
                  title: Text('${names[o.field]}: ${o.value ?? '—'}'),
                  subtitle: Text(
                    '${dayLabel(DateTime.fromMillisecondsSinceEpoch(o.ts))} '
                    '${DateTime.fromMillisecondsSinceEpoch(o.ts).toString().substring(11, 16)} · '
                    '${o.device.startsWith('tel') ? 'телефон' : 'ноутбук'}',
                  ),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}
