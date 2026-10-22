import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/store.dart';
import 'services/desktop.dart';
import 'services/life.dart';
import 'services/reminders.dart';
import 'services/services.dart';
import 'services/sync.dart';
import 'services/updates.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');

  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final store = Store.open(p.join(dir.path, 'zhizn.db'));
  final life = Life(store, filesDir: dir.path);
  final desktop = Desktop.supported ? Desktop() : null;

  Services.i = Services(
    life: life,
    sync: Sync(life),
    notifier: Notifier(life),
    updates: Updates(),
    desktop: desktop,
  );

  if (desktop != null) await desktop.init(startHidden: args.contains('--tray'));
  runApp(const ZhiznApp());

  // Остальное — после показа окна; сбой одной службы не мешает другим
  Future<void> safe(Future<void> Function() f) => f().catchError((Object e) => debugPrint('$e'));
  safe(S.notifier.init);
  safe(() async {
    await S.updates.init();
    await S.updates.check();
  });
  S.sync.start();
  safe(S.life.refreshScheduleIfStale);
  _backup(dir.path, store);
}

/// Резервная копия базы раз в день (на ноутбуке), хранится 14 последних.
void _backup(String dir, Store store) {
  if (!(Platform.isWindows || Platform.isLinux)) return;
  try {
    final bdir = Directory(p.join(dir, 'backup'))..createSync(recursive: true);
    final now = DateTime.now();
    final name = 'zhizn-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.db';
    final f = File(p.join(bdir.path, name));
    if (f.existsSync()) return;
    store.db.execute('VACUUM INTO ?', [f.path]);
    final all = bdir.listSync().whereType<File>().toList()..sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(14)) {
      old.deleteSync();
    }
  } catch (_) {}
}
