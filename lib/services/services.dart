import 'desktop.dart';
import 'life.dart';
import 'reminders.dart';
import 'sync.dart';
import 'updates.dart';

/// Все службы приложения в одном месте.
class Services {
  Services({required this.life, required this.sync, required this.notifier, required this.updates, this.desktop});

  final Life life;
  final Sync sync;
  final Notifier notifier;
  final Updates updates;
  final Desktop? desktop;

  static late Services i;
}

Services get S => Services.i;
