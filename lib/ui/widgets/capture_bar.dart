import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models.dart';
import '../../services/life.dart';
import '../../services/services.dart';
import 'common.dart';

/// Поле быстрой записи. Пишите как удобно — приложение само разложит.
class CaptureBar extends StatefulWidget {
  const CaptureBar({super.key, this.autofocus = false, this.onDone, this.controller, this.focusNode});
  final bool autofocus;
  final VoidCallback? onDone;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<CaptureBar> createState() => CaptureBarState();
}

class CaptureBarState extends State<CaptureBar> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  final List<String> _files = [];
  bool _dragging = false;

  bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void focus() => _focus.requestFocus();

  void addFiles(Iterable<String> paths) => setState(() => _files.addAll(paths));
  void setText(String text) {
    _c.text = text;
    _c.selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  Future<void> _pick() async {
    final r = await FilePicker.pickFiles();
    addFiles(r.map((f) => f.path).whereType<String>());
  }

  /// Ctrl+V с картинкой в буфере обмена (скриншот).
  Future<bool> _pasteImage() async {
    if (!_desktop) return false;
    final bytes = await Pasteboard.image;
    if (bytes == null) {
      final files = await Pasteboard.files();
      if (files.isEmpty) return false;
      addFiles(files);
      return true;
    }
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, 'скриншот_${DateTime.now().millisecondsSinceEpoch}.png'));
    await f.writeAsBytes(bytes);
    addFiles([f.path]);
    return true;
  }

  void _submit() {
    final text = _c.text.trim();
    if (text.isEmpty && _files.isEmpty) return;
    final r = S.life.capture(text, files: List.of(_files));
    _c.clear();
    setState(_files.clear);
    toast(context, _summary(r), action: 'Отменить', onAction: () => S.life.undoCapture(r));
    widget.onDone?.call();
  }

  /// «Записано: «Позвонить маме» — завтра, 19:00» или «Записано: 2 дела, заметка».
  String _summary(CaptureResult r) {
    if (r.created.isEmpty) return 'Сохранено в записи';
    if (r.created.length == 1) {
      final e = S.life.store.get(r.created.first);
      if (e == null) return 'Записано';
      if (e.kind == Kinds.task) {
        final t = Task(e);
        final when = [if (t.due != null) dayLabel(t.due!), ?t.time].join(', ');
        return 'Записано: «${t.title}»${when.isEmpty ? ' — без срока' : ' — $when'}';
      }
      final what = switch (e.kind) {
        Kinds.habit => 'привычка',
        Kinds.goal => 'цель',
        Kinds.note => 'заметка',
        Kinds.journal => 'в журнал',
        _ => 'запись',
      };
      return 'Записано: $what «${e['title'] ?? e['text']}»';
    }
    final counts = <String, int>{};
    for (final id in r.created) {
      final kind = S.life.store.get(id)?.kind;
      counts[kind ?? ''] = (counts[kind ?? ''] ?? 0) + 1;
    }
    final parts = [
      if (counts[Kinds.task] != null) plural(counts[Kinds.task]!, 'дело', 'дела', 'дел'),
      if (counts[Kinds.habit] != null) plural(counts[Kinds.habit]!, 'привычка', 'привычки', 'привычек'),
      if (counts[Kinds.goal] != null) plural(counts[Kinds.goal]!, 'цель', 'цели', 'целей'),
      if (counts[Kinds.note] != null) plural(counts[Kinds.note]!, 'заметка', 'заметки', 'заметок'),
      if (counts[Kinds.journal] != null) plural(counts[Kinds.journal]!, 'запись в журнал', 'записи в журнал', 'записей в журнал'),
    ];
    return 'Записано: ${parts.join(', ')}. Проверить можно в «Последних записях»';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget field = CallbackShortcuts(
      bindings: {
        if (_desktop) const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
      },
      child: TextField(
        controller: _c,
        focusNode: _focus,
        autofocus: widget.autofocus,
        minLines: 1,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        keyboardType: TextInputType.multiline,
        contentInsertionConfiguration: ContentInsertionConfiguration(
          onContentInserted: (c) async {
            if (c.data == null) return;
            final dir = await getTemporaryDirectory();
            final f = File(p.join(dir.path, 'вставка_${DateTime.now().millisecondsSinceEpoch}.png'));
            await f.writeAsBytes(c.data!);
            addFiles([f.path]);
          },
        ),
        decoration: InputDecoration(
          hintText: 'Что нужно сделать или запомнить?',
          helperText: _desktop
              ? 'Enter — записать, Shift+Enter — новая строка. Можно перетащить файл или вставить скриншот'
              : null,
          helperMaxLines: 2,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          prefixIcon: IconButton(
            tooltip: 'Прикрепить фото или файл',
            icon: const Icon(Icons.attach_file),
            onPressed: _pick,
          ),
          suffixIcon: IconButton.filled(
            tooltip: 'Записать',
            icon: const Icon(Icons.arrow_upward),
            onPressed: (_c.text.trim().isEmpty && _files.isEmpty) ? null : _submit,
          ),
        ),
      ),
    );

    if (_desktop) {
      field = Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.keyV, control: true): _PasteIntent()},
        child: Actions(
          actions: {
            _PasteIntent: CallbackAction<_PasteIntent>(onInvoke: (_) async {
              if (!await _pasteImage()) {
                final t = await Clipboard.getData(Clipboard.kTextPlain);
                final s = t?.text;
                if (s != null) {
                  final sel = _c.selection;
                  final start = sel.isValid ? sel.start : _c.text.length;
                  final end = sel.isValid ? sel.end : _c.text.length;
                  _c.text = _c.text.replaceRange(start, end, s);
                  _c.selection = TextSelection.collapsed(offset: start + s.length);
                }
              }
              return null;
            }),
          },
          child: field,
        ),
      );
      field = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) {
          setState(() => _dragging = false);
          addFiles(d.files.map((f) => f.path));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _dragging ? cs.primary : Colors.transparent, width: 2),
          ),
          child: field,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (_files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in _files)
                  InputChip(
                    avatar: Icon(_isImage(f) ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 18),
                    label: Text(p.basename(f), overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() => _files.remove(f)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

bool _isImage(String f) => RegExp(r'\.(png|jpe?g|gif|webp|heic|bmp)$', caseSensitive: false).hasMatch(f);
