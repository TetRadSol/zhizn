import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/services.dart';
import '../widgets/common.dart';
import '../widgets/lesson_tile.dart';

/// Учёба: расписание по дням, посещаемость, ДЗ и зачёты с обратным отсчётом.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});
  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late DateTime _day = _firstDay();
  bool _loading = false;
  final _strip = ScrollController();

  DateTime _firstDay() {
    final now = DateTime.now();
    final today = dayOf(now);
    final l = S.life.schedule.on(today);
    // После последней пары сразу показываем завтра
    if (l.isNotEmpty && l.last.endAt.isBefore(now)) return today.add(const Duration(days: 1));
    return today;
  }

  @override
  void initState() {
    super.initState();
    if (S.life.schedule.byDate.isEmpty) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final err = await S.life.refreshSchedule();
    if (!mounted) return;
    setState(() => _loading = false);
    toast(context, err ?? 'Расписание обновлено');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: S.life,
      builder: (context, _) {
        final life = S.life;
        final cs = Theme.of(context).colorScheme;
        final today = dayOf(DateTime.now());
        final days = List.generate(21, (i) => today.add(Duration(days: i - 1)));
        final lessons = life.schedule.on(_day);
        final exams = life.schedule.exams(today);
        final fetched = life.scheduleFetched;
        final changes = life.pendingScheduleChanges.toSet();

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Учёба', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'Группа ${life.group} · ${fetched == null ? 'расписание ещё не загружено' : 'обновлено ${dayLabel(fetched)}'}',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ]),
                ),
                _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(tooltip: 'Обновить расписание с сайта', icon: const Icon(Icons.refresh), onPressed: _refresh),
              ]),
            ),
            // Полоска дней
            SizedBox(
              height: 74,
              child: ListView.builder(
                controller: _strip,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                itemCount: days.length,
                itemBuilder: (_, i) {
                  final d = days[i];
                  final sel = d == _day;
                  final n = life.schedule.on(d).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _day = d),
                      child: Container(
                        width: 52,
                        decoration: BoxDecoration(
                          color: sel ? cs.primary : (d == today ? cs.primaryContainer : cs.surfaceContainerLow),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(weekdaysShort[d.weekday - 1], style: TextStyle(fontSize: 12, color: sel ? cs.onPrimary : cs.onSurfaceVariant)),
                          Text('${d.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sel ? cs.onPrimary : null)),
                          Text(
                            n == 0 ? '—' : '$n п.${changes.contains(ymd(d)) ? ' •' : ''}',
                            style: TextStyle(fontSize: 11, color: sel ? cs.onPrimary : cs.outline),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            SectionTitle('${dayLabel(_day)[0].toUpperCase()}${dayLabel(_day).substring(1)}${changes.contains(ymd(_day)) ? ' · есть изменения' : ''}'),
            if (lessons.isEmpty)
              EmptyHint(
                icon: Icons.weekend_outlined,
                title: life.schedule.byDate.isEmpty ? 'Расписание не загружено' : 'Пар нет',
                text: life.schedule.byDate.isEmpty ? 'Нажмите ⟳ вверху, нужен интернет' : null,
              ),
            for (final l in lessons) LessonTile(l),
            if (exams.isNotEmpty) ...[
              const SectionTitle('Зачёты и экзамены'),
              for (final e in exams.take(15))
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: e.date.difference(today).inDays <= 7 ? cs.errorContainer : cs.surfaceContainerHighest,
                    child: Text('${e.date.difference(today).inDays}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  title: Text('${e.subject} — ${e.type}'),
                  subtitle: Text('${dayLabel(e.date)}, ${e.start}${e.place != null ? ' · ${e.place}' : ''}'),
                  trailing: Text(_daysLeft(e.date.difference(today).inDays), style: TextStyle(color: cs.onSurfaceVariant)),
                ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Отметка у пары: ✓ был, – уважительная причина, ✗ пропуск. '
                'Напишите «Практикум по ОРП» — приложение само поставит ДЗ к ближайшей паре.',
                style: TextStyle(fontSize: 12.5, color: cs.outline),
              ),
            ),
          ],
        );
      },
    );
  }

  String _daysLeft(int n) {
    if (n == 0) return 'сегодня';
    if (n == 1) return 'завтра';
    final m10 = n % 10, m100 = n % 100;
    final w = (m10 == 1 && m100 != 11) ? 'день' : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 'дня' : 'дней';
    return 'через $n $w';
  }
}
