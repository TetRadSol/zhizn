import 'dart:io';

import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../../data/models.dart';
import '../../services/services.dart';
import '../../services/sync.dart';
import '../widgets/capture_bar.dart';
import '../widgets/common.dart';
import '../widgets/lesson_tile.dart';
import '../widgets/task_tile.dart';
import 'jarvis.dart';
import 'modules/growth.dart';
import 'modules/health.dart';
import 'modules/people.dart';
import 'modules/planning.dart';
import 'modules/progress.dart';
import 'lock.dart';
import 'more.dart';
import 'study.dart';
import 'task_editor.dart';

final captureKey = GlobalKey<CaptureBarState>();

/// Первый экран: поле записи, прогресс дня, пары, дела, привычки и лента записей.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([S.life, S.sync, S.updates, S.lock, S.jarvis]),
      builder: (context, _) {
        final life = S.life;
        final now = DateTime.now();
        final today = dayOf(now);
        final lessons = life.schedule.on(today);
        final afterClasses = lessons.isEmpty || lessons.last.endAt.isBefore(now);
        final tomorrowLessons = life.schedule.on(today.add(const Duration(days: 1)));
        final tasks = life.todayTasks();
        final doneToday = life.doneToday();
        final habits = life.habits.where((h) => h.activeOn(today)).toList();
        final progress = life.dayProgress();
        final plan = life.dayPlan();
        final busy = life.busyNow;
        final cs = Theme.of(context).colorScheme;

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Сегодня', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(dateLong(today), style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                ),
                const LevelChip(),
                IconButton(
                  tooltip: 'Форс-мажор: наряд, сборы',
                  icon: const Icon(Icons.flash_on_outlined),
                  onPressed: () => forceMajeureDialog(context),
                ),
                const _SyncIcon(),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: CaptureBar(key: captureKey),
            ),
            ..._banners(context),
            if (busy != null)
              _Banner(
                icon: Icons.flash_on,
                text: '${busy.title} до ${dayLabel(busy.to)}. Дела с этими сроками перенесены.',
                action: 'Закончилось',
                onAction: () => life.store.patch(busy.id, {'to': ymd(today.subtract(const Duration(days: 1)))}),
              ),
            const FocusSuggestBanner(),
            const DigestCard(),
            const QuestionsCard(),
            // Прогресс дня
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Прогресс дня', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    progress.total == 0 ? 'пока пусто' : '${progress.done} из ${progress.total}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ]),
                const SizedBox(height: 6),
                BlockBar(value: progress.total == 0 ? 0 : progress.done / progress.total, height: 12),
              ]),
            ),
            if (lessons.isNotEmpty && !afterClasses) ...[
              SectionTitle('Пары сегодня', trailing: _toStudy(context)),
              for (final l in lessons) LessonTile(l),
            ],
            if (afterClasses && tomorrowLessons.isNotEmpty) ...[
              SectionTitle(
                'Завтра ${tomorrowLessons.length} пар: с ${tomorrowLessons.first.start} до ${tomorrowLessons.last.end}',
                trailing: _toStudy(context),
              ),
            ],
            DayPlanCard(plan: plan),
            SectionTitle(
              'Дела',
              trailing: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить'),
                onPressed: () => openTaskEditor(context, null, due: today),
              ),
            ),
            if (tasks.isEmpty)
              EmptyHint(
                icon: Icons.task_alt,
                title: doneToday.isEmpty ? 'На сегодня дел нет' : 'Всё сделано — отличный день!',
                text: doneToday.isEmpty ? 'Напишите в поле выше, например: «завтра в 15:00 вождение»' : null,
              ),
            for (final t in tasks) TaskTile(t, showDate: t.due != today),
            if (doneToday.isNotEmpty)
              ExpansionTile(
                title: Text('Сделано сегодня: ${doneToday.length}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                children: [for (final t in doneToday) TaskTile(t, dense: true)],
              ),
            if (habits.isNotEmpty) ...[
              const SectionTitle('Привычки сегодня'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in habits)
                    _HabitChip(title: h.title, mark: h.mark(today), onTap: () => life.cycleHabit(h, today)),
                ]),
              ),
            ],
            const _AlsoToday(),
            if (now.hour >= 18) ...[
              const SectionTitle('Показатели дня'),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: MetricsCard()),
            ],
            const _Feed(),
          ],
        );
      },
    );
  }

  Widget _toStudy(BuildContext context) => TextButton(
    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(body: SafeArea(child: StudyScreen())))),
    child: const Text('Расписание'),
  );

  List<Widget> _banners(BuildContext context) {
    final out = <Widget>[];
    final u = S.updates.available;
    if (u != null) {
      out.add(_Banner(
        icon: Icons.system_update,
        text: 'Вышла новая версия ${u.version}',
        action: 'Обновить',
        onAction: S.updates.install,
      ));
    }
    if (Platform.isAndroid && S.life.store.getKv('phone_setup') == null) {
      out.add(_Banner(
        icon: Icons.notifications_active_outlined,
        text: 'Настройте телефон, чтобы напоминания приходили вовремя (1 минута)',
        action: 'Настроить',
        onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneSetupScreen())),
      ));
    }
    if (!S.lock.enabled && S.life.store.getKv('pin_hint_off') == null) {
      out.add(_Banner(
        icon: Icons.lock_outline,
        text: 'Поставьте PIN, чтобы без вас приложение никто не открыл',
        action: 'Поставить',
        onAction: () => setPinFlow(context),
        onClose: () {
          S.life.store.setKv('pin_hint_off', '1');
          S.life.store.touch();
        },
      ));
    }
    final changes = S.life.pendingScheduleChanges;
    if (changes.isNotEmpty) {
      out.add(_Banner(
        icon: Icons.edit_calendar,
        text: 'Расписание изменилось: ${changes.take(4).map((d) => dayLabel(parseYmd(d)!)).join(', ')}',
        action: 'Понятно',
        onAction: S.life.dismissScheduleChanges,
      ));
    }
    if (!S.sync.configured && S.life.store.getKv('sync_hint_off') == null && S.life.captures.length >= 3) {
      out.add(_Banner(
        icon: Icons.sync,
        text: 'Подключите синхронизацию, чтобы телефон и ноутбук видели одно и то же',
        action: 'Подключить',
        onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen())),
        onClose: () {
          S.life.store.setKv('sync_hint_off', '1');
          S.life.store.touch();
        },
      ));
    }
    return out;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.action, required this.onAction, this.onClose});
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(children: [
            Icon(icon, color: cs.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: cs.onSecondaryContainer))),
            TextButton(onPressed: onAction, child: Text(action)),
            if (onClose != null) IconButton(tooltip: 'Скрыть', icon: const Icon(Icons.close, size: 18), onPressed: onClose),
          ]),
        ),
      ),
    );
  }
}

class _HabitChip extends StatelessWidget {
  const _HabitChip({required this.title, required this.mark, required this.onTap});
  final String title;
  final String? mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (mark) {
      '✓' => (const Color(0xFF2E9E6A), Colors.white),
      '✗' => (const Color(0xFFD9534F), Colors.white),
      '–' => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (cs.surfaceContainerLow, cs.onSurface),
    };
    return Tooltip(
      message: 'Нажмите: ✓ сделано → – пропуск → ✗ не сделано',
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: mark == null ? cs.outlineVariant : Colors.transparent)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text('${mark ?? '○'}  $title', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// Лента последних записей: что написали и во что это превратилось.
class _Feed extends StatelessWidget {
  const _Feed();

  @override
  Widget build(BuildContext context) {
    final caps = S.life.captures.take(6).toList();
    if (caps.isEmpty) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Последние записи'),
      for (final c in caps)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  c.text.isEmpty ? '(только файлы)' : c.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
                ),
              ),
              Text(
                '${c.created.hour.toString().padLeft(2, '0')}:${c.created.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final f in c.files)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.attach_file, size: 16),
                  label: Text(f['name'] as String),
                ),
              for (final id in c.results) _resultChip(context, id),
            ]),
            const SizedBox(height: 2),
            Text(
              c.status == 'jarvis'
                  ? '🤖 Проверено Джарвисом${((c.e['jarvisNotes'] as List?) ?? const []).isEmpty ? '' : ': ${((c.e['jarvisNotes'] as List).cast<String>()).join('; ')}'}'
                  : (c.e['noAi'] == true ? 'не для Джарвиса' : 'Разобрано правилами · Джарвис проверит при следующем разборе'),
              style: TextStyle(fontSize: 12, color: c.status == 'jarvis' ? cs.primary : cs.outline),
            ),
          ]),
        ),
    ]);
  }

  Widget _resultChip(BuildContext context, String id) {
    final e = S.life.store.get(id);
    if (e == null) return const SizedBox();
    final (icon, label) = switch (e.kind) {
      Kinds.task => (Icons.check_box_outlined, Task(e).title + (Task(e).due != null ? ' · ${dayLabel(Task(e).due!)}' : '')),
      Kinds.habit => (Icons.repeat, 'Привычка: ${e['title']}'),
      Kinds.goal => (Icons.flag_outlined, 'Цель: ${e['title']}'),
      Kinds.note => (Icons.lightbulb_outline, 'Заметка: ${e['title']}'),
      Kinds.journal => (Icons.menu_book_outlined, 'Журнал: ${e['text']}'),
      _ => (Icons.circle_outlined, '?'),
    };
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      tooltip: 'Исправить',
      onPressed: e.kind == Kinds.task ? () => openTaskEditor(context, id) : () => openEntityEditor(context, id),
    );
  }
}

class _SyncIcon extends StatelessWidget {
  const _SyncIcon();

  @override
  Widget build(BuildContext context) {
    final s = S.sync;
    if (!s.configured) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: s.busy ? 'Синхронизация…' : (s.lastError ?? 'Синхронизировано ${s.lastOkText}. Нажмите, чтобы обновить'),
      onPressed: s.run,
      icon: s.busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(s.lastError == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: s.lastError == null ? cs.primary : cs.error),
    );
  }
}

/// Открыть системный экран настроек Android для этого приложения.
Future<void> _openAndroidSettings(String action) async {
  try {
    await AndroidIntent(action: action, data: 'package:by.zhizn.zhizn').launch();
  } catch (_) {
    await const AndroidIntent(action: 'android.settings.SETTINGS').launch();
  }
}

/// Настройка телефона Tecno (HiOS): иначе напоминания опаздывают.
class PhoneSetupScreen extends StatefulWidget {
  const PhoneSetupScreen({super.key});
  @override
  State<PhoneSetupScreen> createState() => _PhoneSetupScreenState();
}

class _PhoneSetupScreenState extends State<PhoneSetupScreen> {
  final _done = <int>{};

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Разрешить уведомления', 'Без этого напоминания не появятся.', () async => S.notifier.requestPermissions()),
      ('Точные будильники', 'Чтобы напоминание приходило минута в минуту.', () async => S.notifier.requestExactAlarms()),
      ('Без ограничений батареи', 'HiOS закрывает приложения в фоне. Выберите «Не ограничивать».', () async => _openAndroidSettings('android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')),
      (
        'Автозапуск',
        'Откроются настройки приложения. Включите «Автозапуск» (или «Запуск приложений» → вручную, все переключатели).',
        () async => _openAndroidSettings('android.settings.APPLICATION_DETAILS_SETTINGS')
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Настройка телефона')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Телефоны Tecno закрывают приложения в фоне, из-за этого напоминания могут опаздывать. '
              'Пройдите 4 шага — это один раз.'),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: _done.contains(i) ? const Icon(Icons.check) : Text('${i + 1}')),
                title: Text(steps[i].$1),
                subtitle: Text(steps[i].$2),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    await steps[i].$3();
                    setState(() => _done.add(i));
                  },
                  child: const Text('Открыть'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              S.life.store.setKv('phone_setup', '1');
              S.life.store.touch();
              Navigator.pop(context);
            },
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }
}

/// «Ещё на сегодня»: практики, добавки, дни рождения, кому позвонить, покупки, обзор недели.
class _AlsoToday extends StatelessWidget {
  const _AlsoToday();

  @override
  Widget build(BuildContext context) {
    final life = S.life;
    final today = life.today;
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final chips = <Widget>[];
    final practices = life.store.ofKind(Kinds.practice).where((p) => p['m:${ymd(today)}'] != '✓').length;
    if (practices > 0) chips.add(ActionChip(avatar: const Text('📚'), label: Text('Практики: $practices'), onPressed: () => open(const PracticeScreen())));
    final supps = life.habits.where((h) => h.e['supp'] == true && h.mark(today) == null).length;
    if (supps > 0) chips.add(ActionChip(avatar: const Text('💊'), label: Text('Добавки: $supps'), onPressed: () => open(const HealthScreen())));
    for (final p in life.store.ofKind(Kinds.person)) {
      final b = nextBirthday(p, today);
      if (b != null && b.difference(today).inDays <= 1) {
        chips.add(ActionChip(avatar: const Text('🎂'), label: Text('${p['name']} — ${b == today ? 'сегодня' : 'завтра'}'), onPressed: () => open(const PeopleScreen())));
      }
    }
    final calls = life.store.ofKind(Kinds.person).where((p) => contactDue(p, today)).length;
    if (calls > 0) chips.add(ActionChip(avatar: const Text('📞'), label: Text('Связаться: $calls'), onPressed: () => open(const PeopleScreen())));
    final shop = life.tasks.where((t) => t.type == 'shopping' && !t.done).length;
    if (shop > 0) chips.add(ActionChip(avatar: const Text('🛒'), label: Text('Купить: $shop'), onPressed: () => open(const ShoppingScreen())));
    if (today.weekday == 7 && life.store.get('week:${ymd(mondayOf(today))}')?['score'] == null) {
      chips.add(ActionChip(avatar: const Text('📅'), label: const Text('Обзор недели'), onPressed: () => open(const WeekReviewScreen())));
    }
    if (chips.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Ещё на сегодня'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
    ]);
  }
}
