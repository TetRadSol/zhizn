import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Windows: значок в трее, горячая клавиша и маленькое окно быстрой записи.
class Desktop extends ChangeNotifier with TrayListener, WindowListener {
  static bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Окно сейчас в режиме быстрой записи (маленькое, поверх остальных).
  bool quick = false;
  bool _wasHidden = false;

  static const hotkeyLabel = 'Ctrl + Alt + N';
  static const _full = Size(1100, 760);
  static const _quick = Size(560, 260);

  Future<void> init({bool startHidden = false}) async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(size: _startSize(), minimumSize: const Size(360, 220), center: true, title: 'Жизнь'),
      () async {
        // При автозапуске окно сразу прячется в трей
        if (startHidden) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    try {
      await trayManager.setIcon(Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png');
      await trayManager.setToolTip('Жизнь — $hotkeyLabel для записи');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'open', label: 'Открыть'),
        MenuItem(key: 'quick', label: 'Записать ($hotkeyLabel)'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Выйти'),
      ]));
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('Трей недоступен: $e');
    }

    try {
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        HotKey(
          key: PhysicalKeyboardKey.keyN,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (_) => showQuick(),
      );
    } catch (e) {
      debugPrint('Горячая клавиша недоступна: $e');
    }
  }

  /// ZHIZN_WINDOW=400x860 — открыть окно размером с телефон (для проверки вёрстки).
  static Size _startSize() {
    final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(Platform.environment['ZHIZN_WINDOW'] ?? '');
    return m == null ? _full : Size(double.parse(m[1]!), double.parse(m[2]!));
  }

  Future<void> showFull() async {
    if (quick) {
      quick = false;
      notifyListeners();
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSize(_full);
      await windowManager.center();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// Маленькое окно записи поверх остальных.
  Future<void> showQuick() async {
    _wasHidden = !await windowManager.isVisible() || await windowManager.isMinimized();
    quick = true;
    notifyListeners();
    await windowManager.setSize(_quick);
    await windowManager.center();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
  }

  /// После записи окно возвращается туда, где было.
  Future<void> doneQuick() async {
    if (_wasHidden) {
      await windowManager.hide();
      quick = false;
      notifyListeners();
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSize(_full);
      await windowManager.center();
    } else {
      await showFull();
    }
  }

  @override
  void onTrayIconMouseDown() => showFull();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        showFull();
      case 'quick':
        showQuick();
      case 'exit':
        exitApp();
    }
  }

  /// Крестик прячет окно в трей, чтобы напоминания продолжали приходить.
  @override
  void onWindowClose() async {
    if (quick) {
      await doneQuick();
    } else {
      await windowManager.hide();
    }
  }

  Future<void> exitApp() async {
    await hotKeyManager.unregisterAll();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
