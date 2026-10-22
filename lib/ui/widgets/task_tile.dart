import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../logic/recurrence.dart';
import '../../services/services.dart';
import '../screens/task_editor.dart';
import 'common.dart';

/// Строка задачи: кружок-галочка, название, срок и сфера.
/// Свайп вправо — сделано, влево — на завтра.
class TaskTile extends StatelessWidget {
  const TaskTile(this.task, {super.key, this.showDate = true, this.dense = false});
  final Task task;
  final bool showDate;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final cs = Theme.of(context).colorScheme;
    final today = dayOf(DateTime.now());
    final overdue = !t.done && t.due != null && t.due!.isBefore(today);
    final sphere = Sphere.byId(t.sphere);
    final lesson = t.lessonRef == null ? null : S.life.schedule.byRef(t.lessonRef!);

    final meta = <InlineSpan>[];
    void add(String s, {Color? color, IconData? icon}) {
      if (meta.isNotEmpty) meta.add(const TextSpan(text: '  ·  '));
      if (icon != null) {
        meta.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: const EdgeInsets.only(right: 3), child: Icon(icon, size: 14, color: color ?? cs.onSurfaceVariant)),
        ));
      }
      meta.add(TextSpan(text: s, style: color == null ? null : TextStyle(color: color, fontWeight: FontWeight.w600)));
    }

    if (showDate && t.due != null) add(overdue ? 'просрочено, ${dayLabel(t.due!)}' : dayLabel(t.due!), color: overdue ? cs.error : null);
    if (t.time != null) add(t.duration != null ? '${t.time}, ${t.duration} мин' : t.time!, icon: Icons.schedule);
    if (lesson != null) add('к паре ${lesson.date.day}.${lesson.date.month.toString().padLeft(2, '0')}', icon: Icons.school_outlined);
    if (t.repeat != null) add(Repeat.describe(t.repeat), icon: Icons.repeat);
    if (sphere != null) add(sphere.label);

    final tile = ListTile(
      dense: dense,
      contentPadding: const EdgeInsets.only(left: 4, right: 12),
      leading: IconButton(
        tooltip: t.done ? 'Вернуть' : 'Сделано',
        icon: Icon(
          t.done ? Icons.check_circle : (t.type == 'event' ? Icons.event_outlined : Icons.radio_button_unchecked),
          color: t.done ? const Color(0xFF2E9E6A) : (t.prio == Prio.red ? const Color(0xFFD9534F) : cs.outline),
        ),
        onPressed: () => t.done ? S.life.uncomplete(t) : _complete(context),
      ),
      title: Text(
        '${Prio.emoji(t.prio)} ${t.title}'.trim(),
        style: TextStyle(decoration: t.done ? TextDecoration.lineThrough : null, color: t.done ? cs.outline : null),
      ),
      subtitle: meta.isEmpty
          ? null
          : Text.rich(TextSpan(children: meta), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
      onTap: () => openTaskEditor(context, t.id),
    );

    if (t.done) return tile;
    return Dismissible(
      key: ValueKey('task-${t.id}-${t.due}'),
      background: _swipeBg(context, Icons.check, 'Сделано', const Color(0xFF2E9E6A), Alignment.centerLeft),
      secondaryBackground: _swipeBg(context, Icons.arrow_forward, 'На завтра', cs.tertiary, Alignment.centerRight),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          _complete(context);
        } else {
          S.life.moveTo(t, today.add(const Duration(days: 1)));
          toast(context, 'Перенесено на завтра', action: 'Отменить', onAction: () => S.life.moveTo(t, t.due));
        }
        return false;
      },
      child: tile,
    );
  }

  void _complete(BuildContext context) {
    final before = Task(S.life.store.get(task.id)!);
    final due = before.due;
    S.life.complete(task);
    final after = S.life.task(task.id);
    final msg = (after != null && !after.done && after.due != null)
        ? 'Сделано! Следующий раз — ${dayLabel(after.due!)}'
        : 'Сделано!';
    toast(context, msg, action: 'Отменить', onAction: () {
      S.life.store.patch(task.id, {
        'done': false,
        'doneAt': null,
        'due': due == null ? null : ymd(due),
        'c:${ymd(DateTime.now())}': false,
        'doneCount': before.doneCount,
      });
    });
  }

  Widget _swipeBg(BuildContext context, IconData icon, String text, Color color, Alignment align) {
    return Container(
      color: color.withValues(alpha: 0.18),
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, color: color), const SizedBox(width: 6), Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))],
      ),
    );
  }
}
