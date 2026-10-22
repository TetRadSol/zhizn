import 'package:flutter/material.dart';

import '../../data/models.dart';

const _months = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];
const weekdaysFull = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];
const weekdaysShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

/// «сегодня», «завтра», «пт, 23 октября».
String dayLabel(DateTime d, {DateTime? now}) {
  final t = dayOf(now ?? DateTime.now());
  final diff = dayOf(d).difference(t).inDays;
  if (diff == 0) return 'сегодня';
  if (diff == 1) return 'завтра';
  if (diff == -1) return 'вчера';
  if (diff == 2) return 'послезавтра';
  return '${weekdaysShort[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

String dateLong(DateTime d) => '${weekdaysFull[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// Шкала как в Excel-трекере: ████████░░
class BlockBar extends StatelessWidget {
  const BlockBar({super.key, required this.value, this.blocks = 10, this.color, this.height = 10});
  final double value;
  final int blocks;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final filled = (value.clamp(0, 1) * blocks).round();
    return Row(
      children: [
        for (var i = 0; i < blocks; i++)
          Expanded(
            child: Container(
              height: height,
              margin: EdgeInsets.only(right: i == blocks - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: i < filled ? c : c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}

/// Заголовок раздела на экране.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 20, 8, 6)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Пустой экран с подсказкой, что делать.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 40, color: t.colorScheme.outline),
          const SizedBox(height: 8),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(text!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Отметка ✓ / – / ✗ в клетке.
class MarkCell extends StatelessWidget {
  const MarkCell({super.key, required this.mark, required this.onTap, this.size = 36, this.enabled = true, this.today = false});
  final String? mark;
  final VoidCallback onTap;
  final double size;
  final bool enabled;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (mark) {
      '✓' => (const Color(0xFF2E9E6A), Colors.white),
      '✗' => (const Color(0xFFD9534F), Colors.white),
      '–' => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (Colors.transparent, cs.outline),
    };
    return Semantics(
      button: true,
      label: switch (mark) { '✓' => 'выполнено', '✗' => 'не выполнено', '–' => 'пропуск', _ => 'нет отметки' },
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? bg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: today ? cs.primary : (mark == null && enabled ? cs.outlineVariant : Colors.transparent),
              width: today ? 2 : 1,
            ),
          ),
          child: Text(enabled ? (mark ?? '') : '·', style: TextStyle(color: fg, fontSize: size * 0.45, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

void toast(BuildContext context, String text, {String? action, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 4),
    action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
  ));
}

/// Узкий экран — телефон.
bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 720;

/// 1 запись, 2 записи, 5 записей.
String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n $one';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n $few';
  return '$n $many';
}
