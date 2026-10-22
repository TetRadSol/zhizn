import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/data/models.dart';
import 'package:zhizn/data/store.dart';
import 'package:zhizn/services/lan_crypto.dart';
import 'package:zhizn/services/life.dart';
import 'package:zhizn/services/sync.dart';

void main() {
  test('шифрование: расшифровывается своим ключом, подмена ловится', () {
    final box = Box(Box.randomBytes(32));
    final sealed = box.seal(utf8.encode('Практикум по ОРП'));
    expect(utf8.decode(box.open(sealed)!), 'Практикум по ОРП');
    expect(Box(Box.randomBytes(32)).open(sealed), isNull);
    sealed[20] ^= 1;
    expect(box.open(sealed), isNull);
  });

  test('обмен по курсорам: каждое изменение доходит один раз', () {
    final tel = LanExchange(Store.memory(deviceId: 'tel-a'), filesDir: '/tmp/none');
    final pc = LanExchange(Store.memory(deviceId: 'pc-b'), filesDir: '/tmp/none');
    void round() {
      final r = tel.request('pc-b');
      tel.apply('pc-b', pc.serve('tel-a', r.body), r.sentUpTo);
    }

    final a = tel.store.create(Kinds.task, {'title': 'С телефона'});
    final b = pc.store.create(Kinds.task, {'title': 'С ноутбука'});
    round();
    expect(pc.store.get(a)!['title'], 'С телефона');
    expect(tel.store.get(b)!['title'], 'С ноутбука');

    // Повторный обмен ничего не пересылает
    final r = tel.request('pc-b');
    expect(r.body['ops'], isEmpty);
    expect(pc.serve('tel-a', r.body)['ops'], isEmpty);

    pc.store.patch(a, {'done': true});
    round();
    expect(tel.store.get(a)!['done'], true);
  });

  test('настоящий обмен по сети: связь по коду и синхронизация', () async {
    final dir = Directory.systemTemp.createTempSync('zhizn');
    final pcLife = Life(Store.memory(deviceId: 'pc-b'), filesDir: '${dir.path}/pc');
    final telLife = Life(Store.memory(deviceId: 'tel-a'), filesDir: '${dir.path}/tel');
    final server = Sync(pcLife, server: true);
    final phone = Sync(telLife, server: false);
    server.start();
    await Future.delayed(const Duration(milliseconds: 300));
    expect(server.serving, isTrue);

    final laptop = Found('', 'ноутбук', '127.0.0.1', lanPort);
    expect(await phone.pair(laptop, '000000'), isNotNull, reason: 'неверный код не подходит');
    expect(await phone.pair(laptop, server.pairingCode()), isNull);
    expect(phone.peers.keys, ['pc-b']);
    expect(server.peers.keys, ['tel-a']);

    final t = telLife.store.create(Kinds.task, {'title': 'Постирать постельное'});
    final h = pcLife.store.create(Kinds.habit, {'title': 'Протеин'});
    await phone.run();
    expect(phone.lastError, isNull);
    expect(pcLife.store.get(t)!['title'], 'Постирать постельное');
    expect(telLife.store.get(h)!['title'], 'Протеин');

    server.dispose();
    phone.dispose();
  });
}
