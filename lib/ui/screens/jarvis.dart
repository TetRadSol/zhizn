import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/planner.dart';
import '../../services/jarvis.dart';
import '../../services/mcp.dart';
import '../../services/services.dart';
import '../widgets/common.dart';
import 'task_editor.dart';

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Вопросы Джарвиса: ответ одним нажатием.
class QuestionsCard extends StatelessWidget {
  const QuestionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final qs = S.life.openQuestions;
    if (qs.isEmpty) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Джарвис спрашивает · ${qs.length}'),
      for (final q in qs.take(5))
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Material(
            color: cs.tertiaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('🤖 ${q['text']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (q['task'] != null && S.life.task(q['task'] as String) != null)
                  Text('к делу «${S.life.task(q['task'] as String)!.title}»', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final o in ((q['options'] as List?) ?? const []).cast<String>())
                    ActionChip(label: Text(o), onPressed: () => S.life.answer(q.id, o)),
                  ActionChip(avatar: const Icon(Icons.edit, size: 16), label: const Text('Свой ответ'), onPressed: () => _own(context, q)),
                  TextButton(onPressed: () => S.life.store.patch(q.id, {'skipped': true}), child: const Text('Пропустить')),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }

  Future<void> _own(BuildContext context, Entity q) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${q['text']}'),
        content: TextField(controller: c, autofocus: true, maxLines: 4, minLines: 1, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ответить')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) S.life.answer(q.id, c.text.trim());
  }
}

/// Утренний план и вечерний итог от Джарвиса.
class DigestCard extends StatelessWidget {
  const DigestCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dayOf(now);
    final evening = now.hour >= 19 ? S.life.digest(today, 'evening') : null;
    final morning = S.life.digest(today, 'morning');
    final e = evening ?? (now.hour < 19 ? morning : null);
    if (e == null) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(evening != null ? '🤖 Итог дня от Джарвиса' : '🤖 Джарвис о сегодняшнем дне', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
            const SizedBox(height: 6),
            Text('${e['text']}'),
          ]),
        ),
      ),
    );
  }
}

/// «Что реально успеть»: пары, дела со временем и дела, поставленные в свободные окна.
class DayPlanCard extends StatelessWidget {
  const DayPlanCard({super.key, required this.plan});
  final DayPlan plan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (plan.busyReason != null) return const SizedBox();
    final items = plan.slots.where((s) => s.lesson == null).toList();
    if (items.isEmpty && plan.overflow.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        'Что реально успеть',
        trailing: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('свободно ${plan.freeMinutes ~/ 60} ч ${plan.freeMinutes % 60} мин', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
      ),
      for (final s in items)
        InkWell(
          onTap: s.task == null ? null : () => openTaskEditor(context, s.task!.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 96,
                child: Text('${_hm(s.start)}–${_hm(s.end)}', style: TextStyle(fontWeight: s.fixed ? FontWeight.w700 : FontWeight.w500, color: s.fixed ? cs.primary : null)),
              ),
              Expanded(child: Text('${Prio.emoji(s.task?.prio)} ${s.label}'.trim(), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      if (plan.overflow.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Не помещается: ${plan.overflow.map((t) => t.title).join(', ')}', style: TextStyle(color: cs.error)),
            ),
            TextButton(
              onPressed: () {
                final tomorrow = dayOf(DateTime.now()).add(const Duration(days: 1));
                for (final t in plan.overflow) {
                  S.life.moveTo(t, tomorrow);
                }
                toast(context, 'Перенесено на завтра: ${plan.overflow.length}');
              },
              child: const Text('На завтра'),
            ),
          ]),
        ),
    ]);
  }
}

/// Форс-мажор: «заступаю в наряд», «уезжаю на сборы до …».
Future<void> forceMajeureDialog(BuildContext context) async {
  final today = dayOf(DateTime.now());
  var title = 'Наряд';
  var from = today;
  var to = today;
  final custom = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Форс-мажор'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Дни будут отмечены занятыми, дела с этими сроками перенесутся на день после. Джарвис составит план на возвращение.'),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in ['Наряд', 'Сборы', 'Болею', 'Другое'])
                ChoiceChip(label: Text(t), selected: title == t, onSelected: (_) => setState(() => title = t)),
            ]),
            if (title == 'Другое') TextField(controller: custom, decoration: const InputDecoration(labelText: 'Что случилось')),
            const SizedBox(height: 12),
            Row(children: [
              const Text('С '),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: from, firstDate: today.subtract(const Duration(days: 7)), lastDate: today.add(const Duration(days: 120)));
                  if (d != null) setState(() => from = d.isAfter(to) ? (to = d) : d);
                },
                child: Text(dayLabel(from)),
              ),
              const Text(' по '),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: to, firstDate: from, lastDate: today.add(const Duration(days: 120)));
                  if (d != null) setState(() => to = d);
                },
                child: Text(dayLabel(to)),
              ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отметить')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final name = title == 'Другое' ? (custom.text.trim().isEmpty ? 'Занят' : custom.text.trim()) : title;
  final moved = S.life.forceMajeure(name, from, to);
  S.life.capture('$name с ${from.day}.${from.month} по ${to.day}.${to.month}: составь план на возвращение');
  toast(context, moved.isEmpty ? 'Отмечено: $name' : 'Отмечено: $name. Перенесено дел: ${moved.length}');
}

// ---------- Таймер 10 минут (ноутбук) ----------

const _exitPhrase = 'я сдаюсь и прерываю фокус';

bool focusUsedToday() => S.life.store.getKv('focus_day') == ymd(DateTime.now());

/// Спросить про силы и мотивацию; если сил хватает, а мотивации нет — предложить 10 минут.
Future<void> motivationFlow(BuildContext context, Task t) async {
  if (!Platform.isWindows && !Platform.isLinux) return;
  if (focusUsedToday()) {
    toast(context, 'Таймер фокуса уже был сегодня. Попробуйте просто начать с первого шага — 2 минуты.');
    return;
  }
  Future<bool?> ask(String q) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(q),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
      ],
    ),
  );
  final energy = await ask('Силы на это есть?');
  if (energy == null || !context.mounted) return;
  if (energy == false) {
    toast(context, 'Тогда отдохните 15 минут и возьмите дело полегче. Это дело перенесу на завтра?', action: 'Перенести', onAction: () {
      S.life.moveTo(t, dayOf(DateTime.now()).add(const Duration(days: 1)));
    });
    return;
  }
  final motivation = await ask('А мотивация есть?');
  if (motivation == null || !context.mounted) return;
  if (motivation == true) {
    toast(context, 'Отлично, тогда вперёд! Начните с самого простого шага.');
    return;
  }
  await startFocusLock(context, t, reason: 'Силы есть, мотивации мало — 10 минут, и дело сдвинется.');
}

Future<void> startFocusLock(BuildContext context, Task t, {String? reason}) async {
  S.life.store.setKv('focus_day', ymd(DateTime.now()));
  S.life.store.setKv('focus_suggest', null);
  await Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => FocusLockScreen(task: t, reason: reason)));
}

/// Весь экран на 10 минут: только дело и обратный отсчёт. Закрыть нельзя,
/// аварийный выход — набрать фразу целиком.
class FocusLockScreen extends StatefulWidget {
  const FocusLockScreen({super.key, required this.task, this.reason});
  final Task task;
  final String? reason;

  @override
  State<FocusLockScreen> createState() => _FocusLockScreenState();
}

class _FocusLockScreenState extends State<FocusLockScreen> with WindowListener {
  static const _total = Duration(minutes: 10);
  late final DateTime _end = DateTime.now().add(_total);
  Timer? _t;
  final _phrase = TextEditingController();
  bool _desktop = Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    if (_desktop) {
      windowManager.addListener(this);
      () async {
        try {
          await windowManager.show();
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setFullScreen(true);
          await windowManager.focus();
        } catch (_) {
          _desktop = false;
        }
      }();
    }
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().isAfter(_end)) {
        _finish(done: true);
        return;
      }
      setState(() {});
      // Возвращаем окно, если его попытались свернуть или увести
      if (_desktop) {
        windowManager.isFocused().then((f) {
          if (!f) {
            windowManager.show();
            windowManager.focus();
          }
        });
      }
    });
  }

  @override
  void onWindowMinimize() => windowManager.restore();

  Future<void> _finish({required bool done}) async {
    _t?.cancel();
    if (_desktop) {
      await windowManager.setFullScreen(false);
      await windowManager.setAlwaysOnTop(false);
      windowManager.removeListener(this);
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (done) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('10 минут позади 💪'),
          content: Text('Отлично! Самое трудное — начать. Продолжите «${widget.task.title}» или отметьте сделанным.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Продолжу')),
            FilledButton(
              onPressed: () {
                S.life.complete(widget.task);
                Navigator.pop(context);
              },
              child: const Text('Сделано'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _end.difference(DateTime.now());
    final m = left.inMinutes, s = left.inSeconds % 60;
    final cs = Theme.of(context).colorScheme;
    final steps = widget.task.steps;
    return PopScope(
      canPop: false,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () {}},
        child: Scaffold(
          backgroundColor: cs.surface,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Только одно дело', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(widget.task.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (widget.reason != null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.reason!, textAlign: TextAlign.center)),
                  const SizedBox(height: 24),
                  Text(
                    '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 96, fontWeight: FontWeight.w800, color: cs.primary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  SizedBox(width: 360, child: BlockBar(value: 1 - left.inSeconds / _total.inSeconds, blocks: 20)),
                  if (steps.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    for (final st in steps.take(5)) Text('○ ${st['t']}'),
                  ],
                  const SizedBox(height: 40),
                  Text('Выйти раньше: наберите «$_exitPhrase»', style: TextStyle(color: cs.outline, fontSize: 12)),
                  SizedBox(
                    width: 360,
                    child: TextField(
                      controller: _phrase,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (v) {
                        if (v.trim().toLowerCase() == _exitPhrase) _finish(done: false);
                      },
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Предложение Джарвиса: 10 минут фокуса на деле (на ноутбуке).
class FocusSuggestBanner extends StatelessWidget {
  const FocusSuggestBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows || Platform.isLinux) || focusUsedToday()) return const SizedBox();
    final raw = S.life.store.getKv('focus_suggest');
    if (raw == null) return const SizedBox();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final t = S.life.task(j['task'] as String);
    if (t == null || t.done || j['day'] != ymd(DateTime.now())) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(children: [
            const Text('⏱', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text('Джарвис: 10 минут на «${t.title}». ${j['reason'] ?? ''}')),
            FilledButton(onPressed: () => startFocusLock(context, t, reason: j['reason'] as String?), child: const Text('Начать')),
            IconButton(
              tooltip: 'Не сейчас',
              icon: const Icon(Icons.close),
              onPressed: () {
                S.life.store.setKv('focus_suggest', null);
                S.life.store.touch();
              },
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- Экран «Джарвис» ----------

class JarvisScreen extends StatefulWidget {
  const JarvisScreen({super.key});
  @override
  State<JarvisScreen> createState() => _JarvisScreenState();
}

class _JarvisScreenState extends State<JarvisScreen> {
  String? _claude;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    if (Jarvis.supported) {
      S.jarvis.findClaude().then((c) {
        if (mounted) {
          setState(() {
            _claude = c;
            _searched = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Джарвис')),
      body: ListenableBuilder(
        listenable: Listenable.merge([S.life, S.jarvis]),
        builder: (context, _) {
          final last = Jarvis.lastRun(S.life);
          final pending = S.jarvis.brain.pendingRecords().length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
              'Джарвис — Claude Code на ноутбуке по вашей подписке. Несколько раз в день он разбирает новые записи '
              '(и с телефона тоже): уточняет сроки и длительность, разбивает большое на шаги, читает фото и почерк, '
              'задаёт вопросы, вечером пишет итог дня. Ничего не удаляет, каждое его изменение видно и отменяемо.',
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(last == null || last.ok ? Icons.smart_toy_outlined : Icons.error_outline, color: last == null || last.ok ? cs.primary : cs.error),
                title: Text(last == null ? 'Ещё не запускался' : 'Последний разбор: ${dayLabel(last.at)} в ${_hm(last.at)}'),
                subtitle: Text([
                  if (last != null) last.text,
                  'ждут разбора: $pending',
                ].join(' · ')),
                trailing: !Jarvis.supported
                    ? null
                    : S.jarvis.running
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton.tonal(
                        onPressed: () async {
                          final r = await S.jarvis.run(force: true);
                          if (!context.mounted) return;
                          toast(context, r == null ? (S.jarvis.lastError ?? 'Не получилось') : 'Джарвис: ${r.summary}');
                        },
                        child: const Text('Разобрать сейчас'),
                      ),
              ),
            ),
            if (!Jarvis.supported)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Джарвис работает на ноутбуке. Записи с телефона попадут к нему при синхронизации, а ответы и изменения вернутся обратно.'),
              ),
            if (Jarvis.supported) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Разбирать по расписанию'),
                subtitle: Text('В ${S.jarvis.times.join(', ')}, если есть новые записи или ответы. Вечерний запуск пишет итог дня.'),
                value: S.jarvis.enabled,
                onChanged: (v) => S.jarvis.enabled = v,
              ),
              Wrap(spacing: 6, children: [
                for (final t in S.jarvis.times)
                  InputChip(label: Text(t), onDeleted: () => S.jarvis.times = S.jarvis.times..remove(t)),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Время'),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
                    if (t != null) S.jarvis.times = [...S.jarvis.times, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'];
                  },
                ),
              ]),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_claude != null ? Icons.check_circle : Icons.help_outline, color: _claude != null ? const Color(0xFF2E9E6A) : cs.error),
                title: Text(_claude != null ? 'Claude Code найден' : (_searched ? 'Claude Code не найден' : 'Ищу Claude Code…')),
                subtitle: Text(_claude ?? 'Установите Claude Code и войдите в аккаунт (в терминале: claude). Или укажите путь к claude.exe.'),
                trailing: TextButton(onPressed: _setPath, child: const Text('Путь')),
              ),
              if (S.jarvis.lastError != null) Text(S.jarvis.lastError!, style: TextStyle(color: cs.error)),
              if (Platform.isWindows) ...[
                const Divider(height: 32),
                Text('Разговор с Джарвисом в Claude Desktop', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  'После подключения Джарвис в Claude Desktop видит и меняет ваши дела, расписание и привычки и умеет искать: '
                  '«что я планировал по автошколе в октябре?». «Жизнь» должна быть запущена.',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('Подключить к Claude Desktop'),
                    onPressed: () async {
                      final err = await Mcp.connectClaudeDesktop(S.life.filesDir);
                      if (!context.mounted) return;
                      toast(context, err ?? 'Готово. Полностью закройте Claude Desktop (в трее тоже) и откройте снова.');
                    },
                  ),
                ),
              ],
            ],
            const Divider(height: 32),
            Text('Профиль Джарвиса', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Это Джарвис знает о вас. Правьте как удобно.', style: TextStyle(color: cs.onSurfaceVariant)),
            for (final (key, label) in const [
              ('about', 'Кто я'),
              ('places', 'Места'),
              ('principles', 'Принципы'),
              ('goals', 'Цели'),
              ('tone', 'Как со мной говорить'),
            ])
              _ProfileField(fieldKey: key, label: label),
            Row(children: [
              for (final (key, label) in const [('wake', 'Подъём'), ('sleep', 'Отбой'), ('road', 'Дорога, мин')])
                Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _ProfileField(fieldKey: key, label: label, short: true))),
            ]),
          ]);
        },
      ),
    );
  }

  Future<void> _setPath() async {
    final c = TextEditingController(text: S.jarvis.claudePathOverride ?? _claude ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Путь к Claude Code'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: r'C:\Users\…\.local\bin\claude.exe')),
        actions: [
          TextButton(onPressed: () => launchUrl(Uri.parse('https://claude.com/download')), child: const Text('Где взять')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    S.jarvis.claudePathOverride = c.text;
    final found = await S.jarvis.findClaude();
    if (mounted) setState(() => _claude = found);
  }
}

class _ProfileField extends StatefulWidget {
  const _ProfileField({required this.fieldKey, required this.label, this.short = false});
  final String fieldKey;
  final String label;
  final bool short;
  @override
  State<_ProfileField> createState() => _ProfileFieldState();
}

class _ProfileFieldState extends State<_ProfileField> {
  late final _c = TextEditingController(text: S.life.profile(widget.fieldKey));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _c.text.trim() != S.life.profile(widget.fieldKey)) {
        S.life.setProfile(widget.fieldKey, _c.text.trim());
      }
    });
  }

  @override
  void dispose() {
    if (_c.text.trim() != S.life.profile(widget.fieldKey)) S.life.setProfile(widget.fieldKey, _c.text.trim());
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: _c,
      focusNode: _focus,
      minLines: 1,
      maxLines: widget.short ? 1 : 5,
      decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
    ),
  );
}

