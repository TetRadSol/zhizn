import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../services/services.dart';
import 'screens/habits.dart';
import 'screens/lock.dart';
import 'screens/more.dart';
import 'screens/study.dart';
import 'screens/tasks.dart';
import 'screens/today.dart';
import 'widgets/capture_bar.dart';

const seed = Color(0xFF2A9D74);

class ZhiznApp extends StatelessWidget {
  const ZhiznApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Жизнь',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Shell(),
    );
  }
}

/// Главное окно: вкладки снизу на телефоне, слева на ноутбуке.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  static const _dest = [
    (Icons.today_outlined, Icons.today, 'Сегодня'),
    (Icons.checklist_outlined, Icons.checklist, 'Дела'),
    (Icons.school_outlined, Icons.school, 'Учёба'),
    (Icons.repeat_outlined, Icons.repeat_on, 'Привычки'),
    (Icons.apps_outlined, Icons.apps, 'Разделы'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    S.notifier.onTap = _onNotification;
    if (Platform.isAndroid) {
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_onShared);
      HomeWidget.widgetClicked.listen(_onWidget);
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidget);
      ReceiveSharingIntent.instance.getInitialMedia().then((m) {
        _onShared(m);
        ReceiveSharingIntent.instance.reset();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) S.lock.paused();
    if (state == AppLifecycleState.resumed) {
      S.lock.resumed();
      S.sync.run();
      S.life.refreshScheduleIfStale();
      S.life.store.touch();
    }
  }

  /// «Поделиться» из Telegram, галереи или браузера: текст — в поле, файлы — вложением.
  void _onShared(List<SharedMediaFile> items) {
    if (items.isEmpty) return;
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bar = captureKey.currentState;
      if (bar == null) return;
      final texts = items.where((i) => i.type == SharedMediaType.text || i.type == SharedMediaType.url).map((i) => i.path);
      final files = items.where((i) => i.type != SharedMediaType.text && i.type != SharedMediaType.url).map((i) => i.path);
      if (texts.isNotEmpty) bar.setText(texts.join('\n'));
      bar.addFiles(files);
      bar.focus();
    });
  }

  /// Нажатие на виджет: «Записать» — сразу в поле записи.
  void _onWidget(Uri? uri) {
    if (uri == null) return;
    setState(() => _tab = 0);
    if (uri.host == 'capture') {
      WidgetsBinding.instance.addPostFrameCallback((_) => captureKey.currentState?.focus());
    }
  }

  void _onNotification(NotificationResponse r) {
    final input = r.input?.trim();
    if (r.actionId == 'write' && input != null && input.isNotEmpty) {
      // Записано прямо из шторки
      S.life.capture(input);
      return;
    }
    setState(() => _tab = 0);
    if (r.payload == 'capture' || r.actionId == 'write') {
      WidgetsBinding.instance.addPostFrameCallback((_) => captureKey.currentState?.focus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    super.dispose();
  }

  Widget _page() => switch (_tab) {
    0 => const TodayScreen(),
    1 => const TasksScreen(),
    2 => const StudyScreen(),
    3 => const HabitsScreen(),
    _ => const MoreScreen(),
  };

  @override
  Widget build(BuildContext context) {
    // Быструю запись можно сделать и без PIN: она только добавляет, ничего не показывает.
    return ListenableBuilder(
      listenable: Listenable.merge([S.lock, ?S.desktop]),
      builder: (context, _) {
        if (S.desktop?.quick ?? false) return const QuickCapture();
        if (S.lock.locked) return const LockScreen();
        return _shell(context);
      },
    );
  }

  Widget _shell(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = SafeArea(child: KeyedSubtree(key: ValueKey(_tab), child: _page()));
    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
        ),
      );
    }
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: _tab,
          labelType: NavigationRailLabelType.all,
          onDestinationSelected: (i) => setState(() => _tab = i),
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/icon.png', width: 40)),
          ),
          destinations: [for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: body))),
      ]),
    );
  }
}

/// Маленькое окно записи (Ctrl + Alt + N на ноутбуке).
class QuickCapture extends StatelessWidget {
  const QuickCapture({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => S.desktop?.doneQuick()},
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Быстрая запись', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(onPressed: () => S.desktop?.showFull(), child: const Text('Открыть «Жизнь»')),
            ]),
            const SizedBox(height: 8),
            CaptureBar(autofocus: true, onDone: () => Future.delayed(const Duration(milliseconds: 900), () => S.desktop?.doneQuick())),
            const Spacer(),
            Text('Esc — закрыть', style: TextStyle(color: cs.outline, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
