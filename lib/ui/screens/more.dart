import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../services/desktop.dart';
import '../../services/reminders.dart';
import '../../services/services.dart';
import '../../services/sync.dart';
import '../widgets/common.dart';
import 'habits.dart';
import 'lock.dart';
import 'today.dart';

/// «Ещё»: настройки и редко нужные разделы.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return ListenableBuilder(
      listenable: Listenable.merge([S.life, S.sync, S.updates, S.lock]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Ещё', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Заметки и журнал'),
            subtitle: Text('${plural(S.life.notes.length, 'заметка', 'заметки', 'заметок')}, ${plural(S.life.journal.length, 'запись', 'записи', 'записей')} в журнале'),
            onTap: () => open(const NotesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Все записи'),
            subtitle: const Text('Что вы писали и во что это превратилось'),
            onTap: () => open(const CapturesScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Синхронизация'),
            subtitle: Text(S.sync.configured ? 'Подключено · ${S.sync.lastOkText}' : 'Не подключена — данные только на этом устройстве'),
            onTap: () => open(const SyncScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Вход по PIN'),
            subtitle: Text(S.lock.enabled ? 'Включён · нажмите, чтобы сменить' : 'Выключен — приложение открывается сразу'),
            trailing: S.lock.enabled
                ? TextButton(onPressed: () => S.lock.setPin(null), child: const Text('Выключить'))
                : null,
            onTap: () => setPinFlow(context),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Напоминания'),
            subtitle: Text(Platform.isAndroid
                ? 'Тишина ${ReminderSettings(S.life).quietFrom}–${ReminderSettings(S.life).quietTo}, план в ${ReminderSettings(S.life).morning}'
                : 'План в ${ReminderSettings(S.life).morning}, итог в ${ReminderSettings(S.life).evening}'),
            onTap: () => open(const RemindersScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Группа'),
            subtitle: Text('${S.life.group} · расписание с сайта ФКМ обновляется само раз в день'),
            onTap: () => _pickGroup(context),
          ),
          ListTile(
            leading: const Icon(Icons.abc),
            title: const Text('Словарь сокращений'),
            subtitle: const Text('Чтобы приложение понимало ваши слова: спортмасс, кача…'),
            onTap: () => open(const DictScreen()),
          ),
          if (Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Настройка телефона'),
              subtitle: const Text('Уведомления, батарея, автозапуск'),
              onTap: () => open(const PhoneSetupScreen()),
            ),
          if (Platform.isAndroid)
            SwitchListTile(
              secondary: const Icon(Icons.edit_note),
              title: const Text('Кнопка «Записать» в шторке'),
              subtitle: const Text('Постоянное уведомление для быстрой записи'),
              value: S.life.store.getKv('capture_notif') != '0',
              onChanged: (v) {
                S.life.store.setKv('capture_notif', v ? '1' : '0');
                S.notifier.showCaptureNotification();
                S.life.store.touch();
              },
            ),
          if (Desktop.supported)
            const ListTile(
              leading: Icon(Icons.keyboard_outlined),
              title: Text('Быстрая запись: ${Desktop.hotkeyLabel}'),
              subtitle: Text('Из любой программы откроется маленькое окно записи. Крестик прячет «Жизнь» в трей.'),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text(S.updates.available != null ? 'Обновить до ${S.updates.available!.version}' : 'Проверить обновления'),
            subtitle: Text('Версия ${S.updates.current}${S.updates.error != null ? ' · ${S.updates.error}' : ''}'),
            trailing: S.updates.checking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            onTap: () => S.updates.available != null ? S.updates.install() : S.updates.check(),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Как пользоваться'),
            onTap: () => open(const HelpScreen()),
          ),
        ],
      ),
    );
  }

  void _pickGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Группа'),
        children: [
          for (final g in ['3101', '3102', '3103', '3104', '3105'])
            ListTile(
              title: Text(g),
              trailing: g == S.life.group ? const Icon(Icons.check) : null,
              onTap: () {
                S.life.group = g;
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

/// Подключение синхронизации через личного Telegram-бота.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _token = TextEditingController();
  bool _checking = false;
  String? _error;

  Future<void> _connect() async {
    if (_token.text.trim().isEmpty) {
      setState(() => _error = 'Вставьте ключ бота');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final err = await S.sync.connect(_token.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = err;
    });
    if (err == null) {
      _token.clear();
      S.sync.start();
      toast(context, 'Синхронизация подключена');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Синхронизация')),
      body: ListenableBuilder(
        listenable: S.sync,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (S.sync.configured) ...[
              Card(
                child: ListTile(
                  leading: Icon(S.sync.lastError == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      color: S.sync.lastError == null ? cs.primary : cs.error),
                  title: Text(S.sync.lastError ?? 'Всё синхронизировано'),
                  subtitle: Text('Бот @${S.sync.botName} · последний раз ${S.sync.lastOkText}'
                      '${S.sync.pending > 0 ? ' · не отправлено: ${S.sync.pending}' : ''}'),
                  trailing: S.sync.busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(tooltip: 'Синхронизировать сейчас', icon: const Icon(Icons.sync), onPressed: S.sync.run),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Синхронизация идёт сама: при открытии, через 20 секунд после изменений и каждые 10 минут. '
                'Чат с ботом можно отключить по звуку и не открывать — это служебный чат. '
                'Не открепляйте в нём сообщение «zhizn-index.json».',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: S.sync.disconnect, child: const Text('Отключить на этом устройстве')),
              ),
              const Divider(height: 32),
              const Text('Подключить другого бота', style: TextStyle(fontWeight: FontWeight.w600)),
            ] else ...[
              const Text(
                'Телефон и ноутбук обмениваются изменениями через вашего личного Telegram-бота. '
                'Это бесплатно. На оба устройства вводится один и тот же ключ бота.',
              ),
              const SizedBox(height: 16),
              const _Step(
                1,
                'Создайте бота (один раз)',
                'В Telegram откройте @BotFather → /newbot → придумайте имя (например, Жизнь) и адрес, '
                    'оканчивающийся на bot (например, zhizn_tetrad_bot). BotFather пришлёт ключ вида 123456:ABC…',
                'Открыть @BotFather',
                'https://t.me/BotFather',
              ),
              const _Step(2, 'Напишите своему боту', 'Откройте нового бота по ссылке от BotFather и нажмите «Старт».', null, null),
              const _Step(3, 'Вставьте ключ сюда', 'На втором устройстве — тот же ключ. Перед этим снова напишите боту что угодно.', null, null),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _token,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Ключ бота', hintText: '123456789:AA…', border: OutlineInputBorder()),
              onSubmitted: (_) => _connect(),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: cs.error))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _checking ? null : _connect,
              icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
              label: const Text('Проверить и подключить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.title, this.text, this.button, this.url);
  final int n;
  final String title;
  final String text;
  final String? button;
  final String? url;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 14, child: Text('$n')),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(text),
            if (button != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(button!),
                  onPressed: () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
                ),
              ),
          ]),
        ),
      ]),
    ),
  );
}

/// Время плана, итога и тишины, пока телефон сдан.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  Future<String?> _time(BuildContext context, String cur) async {
    final p = cur.split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ReminderSettings(S.life);
    return Scaffold(
      appBar: AppBar(title: const Text('Напоминания')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) => ListView(children: [
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('План на день'),
            trailing: Text(s.morning, style: const TextStyle(fontSize: 16)),
            onTap: () async => s.morning = await _time(context, s.morning) ?? s.morning,
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Итог дня'),
            trailing: Text(s.evening, style: const TextStyle(fontSize: 16)),
            onTap: () async => s.evening = await _time(context, s.evening) ?? s.evening,
          ),
          ListTile(
            leading: const Icon(Icons.event_repeat_outlined),
            title: const Text('Недельный обзор'),
            subtitle: Wrap(spacing: 4, children: [
              for (var i = 1; i <= 7; i++)
                ChoiceChip(
                  label: Text(weekdaysShort[i - 1]),
                  selected: s.weeklyDay == i,
                  onSelected: (_) => s.weeklyDay = i,
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            trailing: Text(s.weekly, style: const TextStyle(fontSize: 16)),
            onTap: () async => s.weekly = await _time(context, s.weekly) ?? s.weekly,
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.phonelink_lock_outlined),
            title: const Text('Телефон сдан — тишина'),
            subtitle: const Text('На телефоне в эти часы напоминаний нет, в конце приходит сводка пропущенного. На ноутбук напоминания приходят всегда.'),
            value: s.quietOn,
            onChanged: (v) => s.quietOn = v,
          ),
          if (s.quietOn) ...[
            ListTile(
              title: const Text('С'),
              trailing: Text(s.quietFrom, style: const TextStyle(fontSize: 16)),
              onTap: () async => s.quietFrom = await _time(context, s.quietFrom) ?? s.quietFrom,
            ),
            ListTile(
              title: const Text('До'),
              trailing: Text(s.quietTo, style: const TextStyle(fontSize: 16)),
              onTap: () async => s.quietTo = await _time(context, s.quietTo) ?? s.quietTo,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 4, children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(weekdaysShort[i - 1]),
                    selected: s.quietDays.contains(i),
                    onSelected: (v) {
                      final d = s.quietDays.toSet();
                      v ? d.add(i) : d.remove(i);
                      s.quietDays = d.toList();
                    },
                  ),
              ]),
            ),
          ],
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Дела со временем напоминают в своё время, события — за 15 минут. '
              'О сроках сдачи и важных делах 🔴 план на день предупреждает за неделю, за 3 дня и накануне.',
            ),
          ),
        ]),
      ),
    );
  }
}

/// Словарь: слово → сфера. Синхронизируется между устройствами.
class DictScreen extends StatefulWidget {
  const DictScreen({super.key});
  @override
  State<DictScreen> createState() => _DictScreenState();
}

class _DictScreenState extends State<DictScreen> {
  final _word = TextEditingController();
  String _sphere = 'health';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Словарь сокращений')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final d = S.life.dict.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Если в записи встретится это слово, дело попадёт в выбранную сферу. '
                'Названия предметов из расписания приложение знает само.'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(controller: _word, decoration: const InputDecoration(labelText: 'Слово', hintText: 'спортмасс', border: OutlineInputBorder())),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _sphere,
                items: [for (final s in Sphere.all) DropdownMenuItem(value: s.id, child: Text(s.label))],
                onChanged: (v) => setState(() => _sphere = v!),
              ),
              IconButton.filled(
                tooltip: 'Добавить',
                icon: const Icon(Icons.add),
                onPressed: () {
                  S.life.setDictWord(_word.text, _sphere);
                  _word.clear();
                },
              ),
            ]),
            const SizedBox(height: 12),
            for (final e in d)
              ListTile(
                title: Text(e.key),
                subtitle: Text(Sphere.byId(e.value)?.label ?? ''),
                trailing: IconButton(tooltip: 'Убрать', icon: const Icon(Icons.close), onPressed: () => S.life.setDictWord(e.key, null)),
              ),
          ]);
        },
      ),
    );
  }
}

/// Заметки, идеи и журнал (траты, тренировки, вес, настроение).
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Заметки и журнал'),
          bottom: const TabBar(tabs: [Tab(text: 'Заметки'), Tab(text: 'Журнал')]),
        ),
        body: ListenableBuilder(
          listenable: S.life,
          builder: (context, _) {
            final notes = S.life.notes.toList()..sort((a, b) => (b['created'] as String? ?? '').compareTo(a['created'] as String? ?? ''));
            final journal = S.life.journal.toList()..sort((a, b) => (b['created'] as String? ?? '').compareTo(a['created'] as String? ?? ''));
            return TabBarView(children: [
              notes.isEmpty
                  ? const EmptyHint(icon: Icons.lightbulb_outline, title: 'Заметок нет', text: 'Напишите «идея: …» или «заметка: …»')
                  : ListView(children: [
                      for (final n in notes)
                        ListTile(
                          leading: Text(switch (n['type']) { 'idea' => '💡', 'thought' => '💭', 'place' => '📍', _ => '📝' }, style: const TextStyle(fontSize: 22)),
                          title: Text(n['title'] as String? ?? ''),
                          subtitle: Text(Sphere.byId(n['sphere'] as String?)?.label ?? ''),
                          onTap: () => openEntityEditor(context, n.id),
                        ),
                    ]),
              journal.isEmpty
                  ? const EmptyHint(icon: Icons.menu_book_outlined, title: 'Журнал пуст', text: 'Напишите «обед 7,5», «жим 60 на 10», «вес 72,5»')
                  : ListView(children: [
                      for (final j in journal)
                        ListTile(
                          leading: Text(switch (j['type']) { 'money' => '💸', 'workout' => '🏋️', 'weight' => '⚖️', 'mood' => '🙂', _ => '📓' }, style: const TextStyle(fontSize: 22)),
                          title: Text(j['text'] as String? ?? ''),
                          subtitle: Text(j['date'] == null ? '' : dayLabel(parseYmd(j['date'] as String)!)),
                          onTap: () => openEntityEditor(context, j.id),
                        ),
                    ]),
            ]);
          },
        ),
      ),
    );
  }
}

/// Все записи из поля ввода.
class CapturesScreen extends StatelessWidget {
  const CapturesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Все записи')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final caps = S.life.captures;
          if (caps.isEmpty) return const EmptyHint(icon: Icons.history, title: 'Записей пока нет');
          return ListView.builder(
            itemCount: caps.length,
            itemBuilder: (_, i) {
              final c = caps[i];
              final why = ((c.e['why'] as List?) ?? const []).cast<String>().where((x) => x.isNotEmpty).join(' / ');
              return ListTile(
                title: Text(c.text.isEmpty ? '(файлы: ${c.files.length})' : c.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text('${dayLabel(c.created)}, ${c.created.hour.toString().padLeft(2, '0')}:${c.created.minute.toString().padLeft(2, '0')}'
                    ' · создано: ${c.results.length}${why.isNotEmpty ? ' · $why' : ''}'),
              );
            },
          );
        },
      ),
    );
  }
}

/// Простое редактирование заметки, записи журнала, цели или привычки.
Future<void> openEntityEditor(BuildContext context, String id) async {
  final e = S.life.store.get(id);
  if (e == null) return;
  if (e.kind == Kinds.habit) return editHabit(context, Habit(e));
  final field = e.kind == Kinds.journal ? 'text' : 'title';
  final c = TextEditingController(text: e[field] as String? ?? '');
  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(switch (e.kind) { Kinds.goal => 'Цель', Kinds.journal => 'Запись в журнале', _ => 'Заметка' }),
      content: SizedBox(width: 420, child: TextField(controller: c, maxLines: 5, minLines: 1, autofocus: true)),
      actions: [
        TextButton(
          onPressed: () {
            S.life.store.delete(id);
            Navigator.pop(context);
          },
          child: Text('Удалить', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        if (e.kind == Kinds.note)
          TextButton(
            onPressed: () {
              S.life.store.create(Kinds.task, {'title': c.text.trim(), 'sphere': e['sphere']});
              S.life.store.delete(id);
              Navigator.pop(context);
            },
            child: const Text('Сделать делом'),
          ),
        FilledButton(
          onPressed: () {
            S.life.store.patch(id, {field: c.text.trim()});
            Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Как записывать', 'Пишите в поле на экране «Сегодня» как удобно. Несколько дел — с новой строки или через «;». '
          'Приложение само поймёт дату, время, повтор и сферу.'),
      ('Примеры', '«завтра в 15:00 вождение»\n«Практикум по ОРП» — ДЗ к ближайшей паре, срок накануне\n'
          '«Зал по понедельникам и средам в 18:00»\n«Сдать курсовую до 5 ноября 🔴»\n«обед 7,5» — в журнал\n'
          '«идея: …», «привычка: протеин», «цель: права»'),
      ('Дела', 'Кружок слева — сделано. Свайп вправо — сделано, влево — на завтра. Нажмите на дело, чтобы изменить. '
          'После любого действия внизу есть «Отменить».'),
      ('Привычки и пары', 'Нажимайте на клетку: ✓ сделано → – пропуск по причине → ✗ не сделано → пусто.'),
      ('Черновики', 'Пока Джарвис не подключён (этап 2), записи разбирают правила. В ленте «Последние записи» видно, что получилось — нажмите, чтобы поправить.'),
      ('Ноутбук', '${Desktop.hotkeyLabel} — маленькое окно записи поверх всех программ. Файлы можно перетащить в поле, скриншот — вставить Ctrl+V. Крестик прячет приложение в трей.'),
      ('Телефон', '«Поделиться» → «Жизнь» из Telegram, галереи или браузера. Кнопка «Записать» в шторке уведомлений.'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Как пользоваться')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.$1, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(i.$2),
            ]),
          ),
      ]),
    );
  }
}
