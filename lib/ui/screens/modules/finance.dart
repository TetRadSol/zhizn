import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../../data/store.dart';
import '../../../logic/finance.dart';
import '../../../services/services.dart';
import '../../widgets/common.dart';

const _monthNames = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];

/// Финансы: траты текстом, доходы, бюджет на месяц, накопления, долги, чеки. Br и $.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late DateTime _month = DateTime(S.life.today.year, S.life.today.month);
  final _c = TextEditingController();

  void _quick() {
    final t = _c.text.trim();
    final m = parseMoney(t);
    if (m == null) {
      toast(context, 'Напишите сумму: «обед 7,5», «+50 стипендия», «отложил 20», «такси 5\$»');
      return;
    }
    S.life.store.create(Kinds.money, {'date': ymd(S.life.today), 'type': m.type, 'cat': m.cat, 'amount': m.amount, 'currency': m.currency, 'note': m.note});
    _c.clear();
    toast(context, '${MoneyCat.byId(m.cat).label}: ${money(m.amount, m.currency)}');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Финансы'), bottom: const TabBar(tabs: [Tab(text: 'Месяц'), Tab(text: 'Долги')])),
        floatingActionButton: FloatingActionButton(onPressed: () => editMoney(context, null), child: const Icon(Icons.add)),
        body: ListenableBuilder(
          listenable: S.life,
          builder: (context, _) => TabBarView(children: [_monthView(context), const _Debts()]),
        ),
      ),
    );
  }

  Widget _monthView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.life.store;
    final mm = monthMoney(s, _month.year, _month.month);
    final usd = monthMoney(s, _month.year, _month.month, currency: r'$');
    final budget = (s.get('budget')?['m:${_month.year}-${_month.month}'] as num?) ?? (s.get('budget')?['default'] as num?);
    final saved = totalSaved(s);
    final goal = s.get('xlg3');
    final target = num.tryParse('${goal?['target'] ?? ''}');
    final entries = moneyOf(s).where((e) {
      final d = parseYmd(e['date'] as String?);
      return d != null && d.year == _month.year && d.month == _month.month;
    }).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('${_monthNames[_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
      ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _c,
            decoration: const InputDecoration(hintText: 'обед 7,5 · +50 стипендия · отложил 20', border: OutlineInputBorder(), isDense: true),
            onSubmitted: (_) => _quick(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _quick, icon: const Icon(Icons.arrow_upward)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _Box('Доходы', money(mm.income), const Color(0xFF2E9E6A)),
        _Box('Расходы', money(mm.expense), cs.error),
        _Box('Баланс', money(mm.balance), cs.primary),
      ]),
      if (usd.income + usd.expense + usd.saving > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('В долларах: доходы ${money(usd.income, r'$')}, расходы ${money(usd.expense, r'$')}, отложено ${money(usd.saving, r'$')}',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(budget == null ? 'Бюджет на месяц не задан' : 'Бюджет: ${money(mm.expense)} из ${money(budget.toDouble())}'),
        subtitle: budget == null ? null : BlockBar(value: mm.expense / budget, height: 8, color: mm.expense > budget ? cs.error : null),
        trailing: TextButton(onPressed: () => _setBudget(context, budget), child: Text(budget == null ? 'Задать' : 'Изменить')),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Text('🏦', style: TextStyle(fontSize: 22)),
        title: Text('Накоплено всего: ${money(saved)}${target != null ? ' из ${money(target.toDouble())}' : ''}'),
        subtitle: target == null ? null : BlockBar(value: saved / target, height: 8),
      ),
      if (mm.byCat.isNotEmpty) ...[
        const SectionTitle('Расходы по категориям', padding: EdgeInsets.fromLTRB(0, 12, 0, 6)),
        for (final e in (mm.byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 160, child: Text(MoneyCat.byId(e.key).label)),
              Expanded(child: BlockBar(value: e.value / mm.expense, height: 8)),
              SizedBox(width: 80, child: Text(money(e.value), textAlign: TextAlign.right)),
            ]),
          ),
      ],
      SectionTitle('Записи · ${entries.length}', padding: const EdgeInsets.fromLTRB(0, 16, 0, 6)),
      if (entries.isEmpty) Text('Пишите траты прямо в поле записи на «Сегодня»: «обед 7,5».', style: TextStyle(color: cs.onSurfaceVariant)),
      for (final e in entries)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          onTap: () => editMoney(context, e),
          leading: Text(MoneyCat.byId(e['cat'] as String?).label.split(' ').first, style: const TextStyle(fontSize: 20)),
          title: Text('${e['note'] ?? ''}'.isEmpty ? MoneyCat.byId(e['cat'] as String?).label : '${e['note']}'),
          subtitle: Text(dayLabel(parseYmd(e['date'] as String)!)),
          trailing: Text(
            '${e['type'] == 'income' ? '+' : (e['type'] == 'saving' ? '🏦 ' : '−')}${money((e['amount'] as num).toDouble(), (e['currency'] as String?) ?? 'Br')}',
            style: TextStyle(fontWeight: FontWeight.w700, color: e['type'] == 'income' ? const Color(0xFF2E9E6A) : null),
          ),
        ),
    ]);
  }

  Future<void> _setBudget(BuildContext context, num? cur) async {
    final c = TextEditingController(text: cur == null ? '' : '$cur');
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Бюджет на месяц, Br'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить'))],
      ),
    );
    final v = num.tryParse((r ?? '').replaceAll(',', '.'));
    if (v != null) S.life.store.update('budget', 'budget', {'default': v, 'm:${_month.year}-${_month.month}': v});
  }
}

class _Box extends StatelessWidget {
  const _Box(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
    ),
  );
}

Future<void> editMoney(BuildContext context, Entity? e) async {
  final amount = TextEditingController(text: e == null ? '' : '${e['amount']}');
  final note = TextEditingController(text: e?['note'] as String? ?? '');
  var type = (e?['type'] as String?) ?? 'expense';
  var cat = (e?['cat'] as String?) ?? 'food';
  var cur = (e?['currency'] as String?) ?? 'Br';
  var date = parseYmd(e?['date'] as String?) ?? S.life.today;
  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final cats = MoneyCat.all.where((c) => c.type == type).toList();
        if (!cats.any((c) => c.id == cat)) cat = cats.first.id;
        return AlertDialog(
          title: Text(e == null ? 'Запись' : 'Изменить запись'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Расход')),
                    ButtonSegment(value: 'income', label: Text('Доход')),
                    ButtonSegment(value: 'saving', label: Text('Отложил')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setState(() => type = s.first),
                ),
                Row(children: [
                  Expanded(child: TextField(controller: amount, autofocus: e == null, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Сумма'))),
                  const SizedBox(width: 8),
                  DropdownButton<String>(value: cur, items: const [DropdownMenuItem(value: 'Br', child: Text('Br')), DropdownMenuItem(value: r'$', child: Text(r'$'))], onChanged: (v) => setState(() => cur = v!)),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final c in cats) ChoiceChip(label: Text(c.label), selected: cat == c.id, onSelected: (_) => setState(() => cat = c.id)),
                ]),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Комментарий')),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (d != null) setState(() => date = d);
                  },
                  child: Text('Дата: ${dayLabel(date)}'),
                ),
              ]),
            ),
          ),
          actions: [
            if (e != null) TextButton(onPressed: () {
              S.life.store.delete(e.id);
              Navigator.pop(context);
            }, child: const Text('Удалить')),
            FilledButton(
              onPressed: () {
                final a = double.tryParse(amount.text.replaceAll(',', '.'));
                if (a == null) return;
                final f = {'date': ymd(date), 'type': type, 'cat': cat, 'amount': a, 'currency': cur, 'note': note.text.trim()};
                if (e == null) {
                  S.life.store.create(Kinds.money, f);
                } else {
                  S.life.store.patch(e.id, f);
                }
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    ),
  );
}

class _Debts extends StatelessWidget {
  const _Debts();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ds = S.life.store.ofKind(Kinds.debt).toList()..sort((a, b) => (a['closed'] == true ? 1 : 0).compareTo(b['closed'] == true ? 1 : 0));
    double sum(String dir) => ds.where((d) => d['dir'] == dir && d['closed'] != true && (d['currency'] ?? 'Br') == 'Br').fold(0.0, (a, d) => a + (d['amount'] as num).toDouble());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        _Box('Я должен', money(sum('i_owe')), cs.error),
        _Box('Мне должны', money(sum('owed')), const Color(0xFF2E9E6A)),
      ]),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('Долг'))),
      for (final d in ds)
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: () => _edit(context, d),
          leading: Icon(d['dir'] == 'i_owe' ? Icons.call_made : Icons.call_received, color: d['dir'] == 'i_owe' ? cs.error : const Color(0xFF2E9E6A)),
          title: Text('${d['person']} — ${money((d['amount'] as num).toDouble(), (d['currency'] as String?) ?? 'Br')}',
              style: TextStyle(decoration: d['closed'] == true ? TextDecoration.lineThrough : null)),
          subtitle: Text([d['dir'] == 'i_owe' ? 'я должен' : 'мне должны', if (d['due'] != null) 'до ${dayLabel(parseYmd(d['due'] as String)!)}', if ('${d['note'] ?? ''}'.isNotEmpty) '${d['note']}'].join(' · ')),
          trailing: d['closed'] == true ? null : TextButton(onPressed: () => S.life.store.patch(d.id, {'closed': true}), child: const Text('Вернули')),
        ),
    ]);
  }

  Future<void> _edit(BuildContext context, Entity? d) async {
    final person = TextEditingController(text: d?['person'] as String? ?? '');
    final amount = TextEditingController(text: d == null ? '' : '${d['amount']}');
    final note = TextEditingController(text: d?['note'] as String? ?? '');
    var dir = (d?['dir'] as String?) ?? 'i_owe';
    DateTime? due = parseYmd(d?['due'] as String?);
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Долг'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'i_owe', label: Text('Я должен')), ButtonSegment(value: 'owed', label: Text('Мне должны'))],
              selected: {dir},
              onSelectionChanged: (s) => setState(() => dir = s.first),
            ),
            TextField(controller: person, decoration: const InputDecoration(labelText: 'Кто')),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Сумма, Br')),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'За что')),
            TextButton(
              onPressed: () async {
                final x = await showDatePicker(context: context, initialDate: due ?? S.life.today, firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (x != null) setState(() => due = x);
              },
              child: Text(due == null ? 'Вернуть до: не задано' : 'Вернуть до: ${dayLabel(due!)}'),
            ),
          ]),
          actions: [
            if (d != null) TextButton(onPressed: () {
              S.life.store.delete(d.id);
              Navigator.pop(context);
            }, child: const Text('Удалить')),
            FilledButton(
              onPressed: () {
                final a = double.tryParse(amount.text.replaceAll(',', '.'));
                if (a == null || person.text.trim().isEmpty) return;
                final f = {'person': person.text.trim(), 'amount': a, 'dir': dir, 'note': note.text.trim(), 'due': due == null ? null : ymd(due!), 'currency': 'Br'};
                if (d == null) {
                  S.life.store.create(Kinds.debt, f);
                } else {
                  S.life.store.patch(d.id, f);
                }
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
