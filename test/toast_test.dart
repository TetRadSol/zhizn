import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/ui/widgets/common.dart';

void main() {
  testWidgets('уведомление с кнопкой «Отменить» исчезает само и закрывается крестиком', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(onPressed: () => toast(c, 'Сделано!', action: 'Отменить', onAction: () {}), child: const Text('go')),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Сделано!'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.text('Сделано!'), findsNothing);

    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.text('Сделано!'), findsNothing);
  });
}
