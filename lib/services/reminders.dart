import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';
import 'life.dart';

class Reminder {
  Reminder(this.key, this.at, this.title, this.body);
  final String key;
  final DateTime at;
  final String title;
  final String body;
  int get id => (key.hashCode & 0x3fffffff) + 100;
}

/// Настройки напоминаний (хранятся на устройстве).
class ReminderSettings {
  ReminderSettings(this.life);
  final Life life;

  String _get(String k, String def) => life.store.getKv(k) ?? def;
  void _set(String k, String v) {
    life.store.setKv(k, v);
    life.store.touch();
  }

  bool get quietOn => _get('quiet_on', '1') == '1';
  set quietOn(bool v) => _set('quiet_on', v ? '1' : '0');
  String get quietFrom => _get('quiet_from', '08:00');
  set quietFrom(String v) => _set('quiet_from', v);
  String get quietTo => _get('quiet_to', '16:00');
  set quietTo(String v) => _set('quiet_to', v);
  List<int> get quietDays => _get('quiet_days', '1,2,3,4,5,6').split(',').where((x) => x.isNotEmpty).map(int.parse).toList();
  set quietDays(List<int> v) => _set('quiet_days', (v..sort()).join(','));
  String get morning => _get('morning', '06:30');
  set morning(String v) => _set('morning', v);
  String get evening => _get('evening', '21:30');
  set evening(String v) => _set('evening', v);
}

int _min(String hm) {
  final p = hm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

DateTime _at(DateTime day, String hm) => DateTime(day.year, day.month, day.day, _min(hm) ~/ 60, _min(hm) % 60);

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

/// Составляет напоминания на ближайшие дни. Чистая функция — проверяется тестами.
List<Reminder> planReminders(Life life, DateTime now, {required bool phone, int days = 3}) {
  final s = ReminderSettings(life);
  final out = <Reminder>[];
  final today = dayOf(now);
  final tasks = life.tasks.where((t) => !t.done).toList();

  for (var i = 0; i < days; i++) {
    final day = today.add(Duration(days: i));
    // Утренний план
    final lessons = life.schedule.on(day);
    final dayTasks = tasks.where((t) => t.due != null && !t.due!.isAfter(day)).toList()..sort(Life.compareTasks);
    final parts = <String>[];
    if (lessons.isNotEmpty) parts.add('${lessons.length} ${_plural(lessons.length, 'пара', 'пары', 'пар')}');
    if (dayTasks.isNotEmpty) parts.add('${dayTasks.length} ${_plural(dayTasks.length, 'дело', 'дела', 'дел')}');
    final first = dayTasks.take(3).map((t) => '${Prio.emoji(t.prio)}${t.title}'.trim()).join(', ');
    final ladder = <String>[];
    for (final t in tasks.where((t) => t.type == 'deadline' || t.prio == Prio.red)) {
      final d = t.due;
      if (d == null) continue;
      final left = d.difference(day).inDays;
      if (left == 7 || left == 3 || left == 1) {
        ladder.add('${left == 1 ? 'завтра' : 'через $left ${_plural(left, 'день', 'дня', 'дней')}'}: ${t.title}');
      }
    }
    final body = [
      if (parts.isEmpty) 'Свободный день' else parts.join(', '),
      if (first.isNotEmpty) 'Сначала: $first',
      ...ladder.take(3).map((x) => 'Срок $x'),
    ].join('\n');
    out.add(Reminder('morning:${ymd(day)}', _at(day, s.morning), 'План на день', body));
    out.add(Reminder('evening:${ymd(day)}', _at(day, s.evening), 'Итог дня',
        'Отметьте сделанное и привычки, перенесите остальное на завтра.'));
  }

  // Дела со временем
  for (final t in tasks) {
    final at = t.at;
    if (at == null) continue;
    final when = t.type == 'event' ? at.subtract(const Duration(minutes: 15)) : at;
    if (when.isBefore(now) || when.isAfter(today.add(Duration(days: days)))) continue;
    out.add(Reminder(
      'task:${t.id}:${ymd(at)}',
      when,
      t.type == 'event' ? 'Через 15 минут' : 'Пора',
      '${Prio.emoji(t.prio)} ${t.title} — ${t.time}'.trim(),
    ));
  }

  out.removeWhere((r) => r.at.isBefore(now));

  // Телефон сдан: днём напоминания не приходят, в конце — сводка пропущенного.
  if (phone && s.quietOn) {
    final from = _min(s.quietFrom), to = _min(s.quietTo);
    final missed = <String, List<Reminder>>{};
    out.removeWhere((r) {
      final m = r.at.hour * 60 + r.at.minute;
      final quiet = s.quietDays.contains(r.at.weekday) && m >= from && m < to;
      if (quiet) missed.putIfAbsent(ymd(r.at), () => []).add(r);
      return quiet;
    });
    for (final e in missed.entries) {
      final day = parseYmd(e.key)!;
      final items = e.value.where((r) => r.key.startsWith('task:')).map((r) => r.body).toList();
      if (items.isEmpty) continue;
      out.add(Reminder('quiet:${e.key}', _at(day, s.quietTo), 'Пока телефон был сдан', items.join('\n')));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Показывает напоминания: на телефоне — через будильники Android,
/// на ноутбуке — пока приложение работает в трее.
class Notifier {
  Notifier(this.life);
  final Life life;
  final plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _tick;
  Timer? _debounce;
  final _shown = <String>{};

  /// Вызывается при нажатии на уведомление или кнопку «Записать».
  void Function(NotificationResponse r)? onTap;

  static bool get isPhone => Platform.isAndroid;
  static const captureId = 1;

  Future<void> init() async {
    if (!(Platform.isAndroid || Platform.isWindows)) return;
    tzdata.initializeTimeZones();
    try {
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Minsk'));
    }
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          linux: LinuxInitializationSettings(defaultActionName: 'Открыть'),
          windows: WindowsInitializationSettings(
            appName: 'Жизнь',
            appUserModelId: 'Zhizn.Zhizn.App',
            guid: '6b1f3c2e-8f4a-4d7b-9c55-2a7e1f0d9b31',
          ),
        ),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Уведомления недоступны: $e');
      return;
    }
    life.addListener(_schedule);
    if (isPhone) {
      final launch = await plugin.getNotificationAppLaunchDetails();
      final r = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && r != null) {
        Future.delayed(const Duration(milliseconds: 600), () => onTap?.call(r));
      }
      await showCaptureNotification();
    } else {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) => _desktopTick());
    }
    _schedule();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> requestPermissions() async {
    final a = _android;
    if (a == null) return true;
    final ok = await a.requestNotificationsPermission() ?? false;
    await a.requestExactAlarmsPermission();
    return ok;
  }

  /// Постоянное уведомление с кнопкой «Записать» (Android).
  Future<void> showCaptureNotification() async {
    if (!_ready || !isPhone) return;
    if (life.store.getKv('capture_notif') == '0') {
      await plugin.cancel(id: captureId);
      return;
    }
    await plugin.show(
      id: captureId,
      title: 'Жизнь',
      body: 'Нажмите, чтобы быстро записать мысль или дело',
      payload: 'capture',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'capture',
          'Быстрая запись',
          channelDescription: 'Постоянная кнопка «Записать»',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          playSound: false,
          enableVibration: false,
          actions: [
            AndroidNotificationAction(
              'write',
              'Записать',
              showsUserInterface: true,
              cancelNotification: false,
              inputs: [AndroidNotificationActionInput(label: 'Что записать?')],
            ),
          ],
        ),
      ),
    );
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Напоминания',
      channelDescription: 'Дела, план на день, итог дня',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    ),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _apply);
  }

  Future<void> _apply() async {
    if (!_ready || !isPhone) return;
    final plan = planReminders(life, DateTime.now(), phone: true);
    final a = _android;
    final exact = await a?.canScheduleExactNotifications() ?? false;
    final pending = await plugin.pendingNotificationRequests();
    final want = {for (final r in plan) r.id};
    for (final p in pending) {
      if (p.id != captureId && !want.contains(p.id)) await plugin.cancel(id: p.id);
    }
    for (final r in plan) {
      try {
        await plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: r.key,
        );
      } catch (e) {
        debugPrint('Не удалось запланировать: $e');
      }
    }
  }

  void _desktopTick() {
    final now = DateTime.now();
    for (final r in planReminders(life, now.subtract(const Duration(minutes: 1)), phone: false, days: 1)) {
      if (r.at.isAfter(now) || _shown.contains(r.key)) continue;
      _shown.add(r.key);
      plugin.show(id: r.id, title: r.title, body: r.body, notificationDetails: _details, payload: r.key);
    }
  }

  void dispose() {
    _tick?.cancel();
    _debounce?.cancel();
  }
}
