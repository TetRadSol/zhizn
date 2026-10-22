import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhizn/data/models.dart';
import 'package:zhizn/data/store.dart';
import 'package:zhizn/services/sync.dart';

/// Поддельный чат с ботом: хранит сообщения с файлами и закреплённое сообщение.
class FakeChat implements TgApi {
  final files = <String, List<int>>{};
  final messages = <int, Map<String, dynamic>>{};
  int? pinned;
  int _id = 0;
  int sent = 0;

  Map<String, dynamic> _doc(String name, List<int> bytes) {
    final fid = 'f${_id++}';
    files[fid] = bytes;
    return {'file_id': fid, 'file_name': name};
  }

  @override
  Future<dynamic> call(String method, [Map<String, String> params = const {}]) async {
    switch (method) {
      case 'getChat':
        return {'id': 1, 'type': 'private', if (pinned != null) 'pinned_message': messages[pinned]};
      case 'pinChatMessage':
        pinned = int.parse(params['message_id']!);
        return true;
    }
    throw TgError(400, 'unknown $method');
  }

  @override
  Future<dynamic> upload(String method, Map<String, String> params, String field, String filename, List<int> bytes) async {
    if (method == 'sendDocument') {
      sent++;
      final id = _id++;
      return messages[id] = {'message_id': id, 'document': _doc(filename, bytes)};
    }
    if (method == 'editMessageMedia') {
      final id = int.parse(params['message_id']!);
      return messages[id] = {'message_id': id, 'document': _doc(filename, bytes)};
    }
    throw TgError(400, 'unknown $method');
  }

  @override
  Future<List<int>> download(String fileId) async => files[fileId]!;
}

void main() {
  test('телефон и ноутбук обмениваются через чат с ботом', () async {
    final chat = FakeChat();
    final tel = Store.memory(deviceId: 'tel-a');
    final pc = Store.memory(deviceId: 'pc-b');
    TgSyncEngine eng(Store s) => TgSyncEngine(s, chat, '1', filesDir: '/tmp');

    final a = tel.create(Kinds.task, {'title': 'Постирать постельное'});
    await eng(tel).run();
    expect(chat.pinned, isNotNull, reason: 'список изменений закреплён');
    expect(tel.pendingOps(), isEmpty);

    final b = pc.create(Kinds.task, {'title': 'Практикум по ОРП'});
    await eng(pc).run();
    expect(pc.get(a)!['title'], 'Постирать постельное');

    await eng(tel).run();
    expect(tel.get(b)!['title'], 'Практикум по ОРП');

    // Повторный обмен без изменений ничего не отправляет
    final before = chat.sent;
    await eng(tel).run();
    await eng(pc).run();
    expect(chat.sent, before);
  });

  test('потерянная строка списка возвращается при следующем обмене', () async {
    final chat = FakeChat();
    final tel = Store.memory(deviceId: 'tel-a');
    final pc = Store.memory(deviceId: 'pc-b');
    TgSyncEngine eng(Store s) => TgSyncEngine(s, chat, '1', filesDir: '/tmp');

    final a = tel.create(Kinds.task, {'title': 'A'});
    await eng(tel).run();
    // Как будто другое устройство одновременно перезаписало список без строки телефона
    final msg = chat.messages[chat.pinned]!;
    chat.messages[chat.pinned!] = {
      'message_id': chat.pinned,
      'document': {'file_id': 'empty', 'file_name': TgSyncEngine.indexName},
    };
    chat.files['empty'] = utf8.encode(jsonEncode({'v': 1, 'files': []}));
    expect(msg, isNotNull);

    await eng(tel).run(); // телефон снова дописывает свои файлы
    await eng(pc).run();
    expect(pc.get(a)!['title'], 'A');
  });
}
