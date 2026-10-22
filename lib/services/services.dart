import 'desktop.dart';
import 'jarvis.dart';
import 'life.dart';
import 'lock.dart';
import 'reminders.dart';
import 'sync.dart';
import 'tg_inbox.dart';
import 'updates.dart';

/// Все службы приложения в одном месте.
class Services {
  Services({required this.life, required this.sync, required this.notifier, required this.updates, required this.lock, required this.jarvis, required this.tg, this.desktop});

  final Life life;
  final Sync sync;
  final Notifier notifier;
  final Updates updates;
  final Lock lock;
  final Jarvis jarvis;
  final TgInbox tg;
  final Desktop? desktop;

  static late Services i;
}

Services get S => Services.i;
