import 'package:flutter/material.dart';

import '../../logic/schedule.dart';
import '../../services/services.dart';
import '../screens/task_editor.dart';
import 'common.dart';

/// Пара: время, предмет, вид, преподаватели, место и отметка посещения.
class LessonTile extends StatelessWidget {
  const LessonTile(this.lesson, {super.key, this.showTasks = true});
  final Lesson lesson;
  final bool showTasks;

  @override
  Widget build(BuildContext context) {
    final l = lesson;
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final live = now.isAfter(l.startAt) && now.isBefore(l.endAt);
    final past = now.isAfter(l.endAt);
    final hw = showTasks ? S.life.tasksForLesson(l) : const [];
    final details = [
      ?l.type,
      if (l.topic != null) l.topic!,
      if (l.place != null) l.place!,
      if (l.teachers.isNotEmpty) l.teachers.join(', '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: live ? cs.primaryContainer : (l.isExam ? cs.errorContainer.withValues(alpha: 0.5) : cs.surfaceContainerLow),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.start, style: TextStyle(fontWeight: FontWeight.w700, color: past ? cs.outline : null)),
                  Text(l.end, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  Text('${l.n} пара', style: TextStyle(fontSize: 11, color: cs.outline)),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${l.isExam ? '📝 ' : ''}${l.subject}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: past ? cs.onSurfaceVariant : null),
                  ),
                  if (details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(details, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                    ),
                  for (final t in hw)
                    InkWell(
                      onTap: () => openTaskEditor(context, t.id),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(t.done ? Icons.check_circle : Icons.assignment_outlined, size: 16, color: t.done ? const Color(0xFF2E9E6A) : cs.primary),
                          const SizedBox(width: 4),
                          Expanded(child: Text('ДЗ: ${t.title}', style: TextStyle(fontSize: 12.5, color: cs.primary))),
                        ]),
                      ),
                    ),
                ]),
              ),
              Tooltip(
                message: 'Посещение: нажмите, чтобы отметить ✓ был, – уважительная, ✗ пропуск',
                child: MarkCell(
                  mark: S.life.lessonMark(l),
                  size: 32,
                  onTap: () => S.life.cycleLesson(l),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
