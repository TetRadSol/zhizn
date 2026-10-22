import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../data/models.dart';
import 'life.dart';

/// Обновляет виджет на рабочем столе Android: сколько дел и пар сегодня и первые дела.
class WidgetUpdater {
  WidgetUpdater(this.life);
  final Life life;
  Timer? _t;

  void start() {
    if (!Platform.isAndroid) return;
    life.addListener(_schedule);
    _push();
  }

  void _schedule() {
    _t?.cancel();
    _t = Timer(const Duration(seconds: 3), _push);
  }

  Future<void> _push() async {
    try {
      final tasks = life.todayTasks();
      final lessons = life.schedule.on(life.today);
      final done = life.doneToday().length;
      final summary = [
        if (lessons.isNotEmpty) '${lessons.length} пар',
        tasks.isEmpty ? (done > 0 ? 'всё сделано ✓' : 'дел нет') : 'дел: ${tasks.length}',
      ].join(' · ');
      await HomeWidget.saveWidgetData<String>('summary', 'Сегодня: $summary');
      await HomeWidget.saveWidgetData<String>(
        'tasks',
        tasks.take(5).map((t) => '${t.time != null ? '${t.time} ' : ''}${Prio.emoji(t.prio)} ${t.title}'.trim()).map((s) => '• $s').join('\n'),
      );
      await HomeWidget.updateWidget(androidName: 'ZhiznWidget', qualifiedAndroidName: 'by.zhizn.zhizn.ZhiznWidget');
    } catch (_) {}
  }
}
