import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../data/store.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';

/// Ближайший день рождения человека (если указан день и месяц).
DateTime? nextBirthday(Entity p, DateTime today) {
  final b = p['birthday'] as String?;
  if (b == null) return null;
  final parts = b.split('-').map(int.tryParse).toList();
  if (parts.length < 2 || parts.any((x) => x == null)) return null;
  final (m, d) = parts.length == 3 ? (parts[1]!, parts[2]!) : (parts[0]!, parts[1]!);
  var x = DateTime(today.year, m, d);
  if (x.isBefore(today)) x = DateTime(today.year + 1, m, d);
  return x;
}

/// Пора связаться: прошло больше «раз в N дней» с последнего контакта.
bool contactDue(Entity p, DateTime today) {
  final every = (p['every'] as num?)?.toInt();
  if (every == null || every <= 0) return false;
  final last = parseYmd(p['last'] as String?);
  return last == null || !last.add(Duration(days: every)).isAfter(today);
}

/// Люди: дни рождения, «позвонить, написать» с напоминанием, карточки с заметками.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Люди')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => editPerson(context, null), icon: const Icon(Icons.person_add), label: const Text('Человек')),
      body: ListenableBuilder(
        listenable: S.life,
        builder: (context, _) {
          final today = S.life.today;
          final ps = S.life.store.ofKind(Kinds.person).toList()..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
          final due = ps.where((p) => contactDue(p, today)).toList();
          final bdays = ps.where((p) => nextBirthday(p, today) != null).toList()
            ..sort((a, b) => nextBirthday(a, today)!.compareTo(nextBirthday(b, today)!));
          final cs = Theme.of(context).colorScheme;
          if (ps.isEmpty) {
            return const EmptyHint(icon: Icons.people_outline, title: 'Пока никого', text: 'Добавьте близких: день рождения, как часто звонить, заметки о человеке.');
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            if (due.isNotEmpty) ...[
              const SectionTitle('Пора связаться', padding: EdgeInsets.fromLTRB(4, 8, 0, 6)),
              for (final p in due)
                Card(
                  color: cs.tertiaryContainer.withValues(alpha: 0.5),
                  child: ListTile(
                    leading: const Text('📞', style: TextStyle(fontSize: 22)),
                    title: Text('${p['name']}'),
                    subtitle: Text(p['last'] == null ? 'ещё не отмечали' : 'последний раз ${dayLabel(parseYmd(p['last'] as String)!)}'),
                    trailing: FilledButton.tonal(onPressed: () => S.life.store.patch(p.id, {'last': ymd(today)}), child: const Text('Связался')),
                  ),
                ),
            ],
            if (bdays.isNotEmpty) ...[
              const SectionTitle('Дни рождения', padding: EdgeInsets.fromLTRB(4, 16, 0, 6)),
              for (final p in bdays.take(5))
                ListTile(
                  leading: const Text('🎂', style: TextStyle(fontSize: 22)),
                  title: Text('${p['name']}'),
                  trailing: Text(
                    nextBirthday(p, today) == today ? 'сегодня!' : '${dayLabel(nextBirthday(p, today)!)} · через ${nextBirthday(p, today)!.difference(today).inDays} дн.',
                    style: TextStyle(color: nextBirthday(p, today)!.difference(today).inDays <= 7 ? cs.error : null),
                  ),
                ),
            ],
            const SectionTitle('Все', padding: EdgeInsets.fromLTRB(4, 16, 0, 6)),
            for (final p in ps)
              ListTile(
                leading: CircleAvatar(child: Text('${p['name']}'.isEmpty ? '?' : '${p['name']}'[0])),
                title: Text('${p['name']}'),
                subtitle: Text([
                  if (p['every'] != null) 'связь раз в ${p['every']} дн.',
                  if ('${p['notes'] ?? ''}'.isNotEmpty) '${p['notes']}',
                ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => editPerson(context, p),
              ),
          ]);
        },
      ),
    );
  }
}

Future<void> editPerson(BuildContext context, Entity? p) async {
  final name = TextEditingController(text: p?['name'] as String? ?? '');
  final notes = TextEditingController(text: p?['notes'] as String? ?? '');
  final every = TextEditingController(text: '${p?['every'] ?? ''}');
  final bday = TextEditingController(text: () {
    final b = p?['birthday'] as String?;
    if (b == null) return '';
    final x = b.split('-');
    return x.length == 3 ? '${x[2]}.${x[1]}.${x[0]}' : '${x[1]}.${x[0]}';
  }());
  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(p == null ? 'Новый человек' : '${p['name']}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: p == null, decoration: const InputDecoration(labelText: 'Имя'), textCapitalization: TextCapitalization.words),
          TextField(controller: bday, decoration: const InputDecoration(labelText: 'День рождения', hintText: '14.03 или 14.03.2003')),
          TextField(controller: every, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Связываться раз в … дней', hintText: '7')),
          TextField(controller: notes, maxLines: 4, minLines: 2, decoration: const InputDecoration(labelText: 'Заметки', hintText: 'что любит, о чём говорили, идеи подарков')),
        ]),
      ),
      actions: [
        if (p != null) TextButton(onPressed: () {
          S.life.store.delete(p.id);
          Navigator.pop(context);
        }, child: const Text('Удалить')),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) return;
            final m = RegExp(r'^(\d{1,2})[./](\d{1,2})(?:[./](\d{4}))?$').firstMatch(bday.text.trim());
            String? b;
            if (m != null) {
              final dd = m[1]!.padLeft(2, '0'), mm = m[2]!.padLeft(2, '0');
              b = m[3] != null ? '${m[3]}-$mm-$dd' : '$mm-$dd';
            }
            final f = {'name': name.text.trim(), 'birthday': b, 'every': int.tryParse(every.text.trim()), 'notes': notes.text.trim()};
            if (p == null) {
              S.life.store.create(Kinds.person, f);
            } else {
              S.life.store.patch(p.id, f);
            }
            Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}
