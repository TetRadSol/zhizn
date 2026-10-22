import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/services.dart';

/// Экран ввода PIN: цифры крупно, удобно одной рукой.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, required this.onDone, this.subtitle, this.error, this.footer});
  final String title;
  final String? subtitle;
  final String? error;
  final Widget? footer;

  /// Вызывается с введённым PIN; верните false, чтобы очистить поле (неверный PIN).
  final bool Function(String pin) onDone;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _shake = false;
  static const _len = 4;

  void _tap(String d) {
    if (_pin.length >= _len) return;
    setState(() => _pin += d);
    if (_pin.length == _len) {
      final ok = widget.onDone(_pin);
      if (!ok) {
        HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _shake = true;
        });
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _shake = false);
        });
      }
    }
  }

  void _back() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 72,
        height: 72,
        child: label.isEmpty && icon == null
            ? null
            : Material(
                color: icon == null ? cs.surfaceContainerHigh : Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap ?? () => _tap(label),
                  child: Center(child: icon != null ? Icon(icon) : Text(label, style: const TextStyle(fontSize: 28))),
                ),
              ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i <= 9; i++) SingleActivator(LogicalKeyboardKey(0x30 + i)): () => _tap('$i'),
        for (var i = 0; i <= 9; i++) SingleActivator(LogicalKeyboardKey(0x200000030 + i)): () => _tap('$i'),
        const SingleActivator(LogicalKeyboardKey.backspace): _back,
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/icon.png', width: 56)),
              const SizedBox(height: 16),
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(widget.subtitle!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              const SizedBox(height: 20),
              AnimatedSlide(
                offset: _shake ? const Offset(0.05, 0) : Offset.zero,
                duration: const Duration(milliseconds: 80),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < _len; i++)
                    Container(
                      margin: const EdgeInsets.all(8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? cs.primary : Colors.transparent,
                        border: Border.all(color: cs.primary, width: 2),
                      ),
                    ),
                ]),
              ),
              SizedBox(
                height: 24,
                child: widget.error == null ? null : Text(widget.error!, style: TextStyle(color: cs.error)),
              ),
              for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
                Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                key(''),
                key('0'),
                key('⌫', icon: Icons.backspace_outlined, onTap: _back),
              ]),
              ?widget.footer,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Экран блокировки при входе.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PinPad(
          title: 'Жизнь',
          subtitle: 'Введите PIN',
          error: _error,
          onDone: (pin) {
            final lock = S.lock;
            if (lock.unlock(pin)) return true;
            setState(() => _error = lock.blockedUntil != null && DateTime.now().isBefore(lock.blockedUntil!)
                ? 'Много попыток. Подождите 30 секунд'
                : 'Неверный PIN');
            return false;
          },
          footer: TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Забыли PIN?'),
                content: const Text(
                  'PIN восстановить нельзя. Можно очистить данные приложения в настройках телефона '
                  '(Приложения → Жизнь → Хранилище → Очистить) и заново подключить синхронизацию — '
                  'все записи вернутся с другого устройства.',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно'))],
              ),
            ),
            child: const Text('Забыли PIN?'),
          ),
        ),
      ),
    );
  }
}

/// Задать или сменить PIN: ввести дважды.
Future<void> setPinFlow(BuildContext context) async {
  String? first;
  String? error;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Scaffold(
          appBar: AppBar(title: const Text('PIN для входа')),
          body: PinPad(
            key: ValueKey(first),
            title: first == null ? 'Придумайте PIN из 4 цифр' : 'Повторите PIN',
            error: error,
            onDone: (pin) {
              if (first == null) {
                setState(() {
                  first = pin;
                  error = null;
                });
                return true;
              }
              if (pin != first) {
                setState(() {
                  first = null;
                  error = 'Не совпало, попробуйте ещё раз';
                });
                return false;
              }
              S.lock.setPin(pin);
              Navigator.pop(context);
              return true;
            },
          ),
        ),
      ),
    ),
  );
}
