import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../models/note_collection.dart';
import '../providers/note_provider.dart';
import '../providers/collection_provider.dart';
import '../services/note_local_store.dart';
import '../theme/app_theme.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.note,
    this.collection,
    required this.noteProvider,
  });

  final NoteModel? note;
  final NoteCollection? collection;
  final NoteProvider noteProvider;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();
  bool _refreshing = false;
  bool _saving = false;
  bool _keyboardVisible = false;
  List<String> _tags = [];
  // 提前缓存，dispose 时不能再用 context
  CollectionProvider? _collectionProvider;
  Timer? _debounceTimer;
  Timer? _remoteSyncTimer;
  String? _newCreatedBid;
  String _lastSyncedTitle = '';
  String _lastSyncedContent = '';
  bool _applyingText = false;
  bool _remoteSyncing = false;
  bool _remoteSyncQueued = false;
  int _editRevision = 0;

  bool get _isEditing => widget.note != null;
  bool get _isEffectivelyEditing => _isEditing || _newCreatedBid != null;
  String? get _currentBid => _isEditing ? widget.note!.bid : _newCreatedBid;
  bool get _hasContent =>
      (widget.note?.title.isNotEmpty ?? false) ||
      (widget.note?.content.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.note?.content ?? '');
    _lastSyncedTitle = _titleCtrl.text;
    _lastSyncedContent = _contentCtrl.text;
    _tags = List<String>.from(widget.note?.tags ?? []);
    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLatest());
    }
    _titleCtrl.addListener(_onTextChanged);
    _contentCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_applyingText) return;
    _editRevision++;

    // 1. 快速本地缓存 (500ms)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveLocal();
    });

    // 2. 较慢的远程同步 (3000ms)
    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = Timer(const Duration(milliseconds: 3000), () {
      _syncRemote();
    });
  }

  Future<void> _saveLocal() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    // 仅当内容真正改变时才处理
    if (title == _lastSyncedTitle && content == _lastSyncedContent) {
      return;
    }

    // 如果是新文档且没写内容，不创建
    if (!_isEffectivelyEditing && title.isEmpty && content.isEmpty) {
      return;
    }

    if (_isEffectivelyEditing) {
      await widget.noteProvider.updateNoteLocal(
        bid: _currentBid!,
        title: title,
        content: content,
      );
    } else {
      // 第一次输入内容的新文档，直接创建
      final targetCollection =
          widget.collection ?? _collectionProvider?.defaultCollection;
      if (targetCollection != null) {
        final newNote = await widget.noteProvider.createNote(
          title: title.isEmpty ? '无标题' : title,
          content: content,
          collectionBid: targetCollection.bid,
        );
        _newCreatedBid = newNote.bid;
        _lastSyncedTitle = title;
        _lastSyncedContent = content;
      }
    }
  }

  Future<void> _syncRemote() async {
    if (_remoteSyncing) {
      _remoteSyncQueued = true;
      return;
    }

    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    // 仅当内容真正改变时才提交
    if (title == _lastSyncedTitle && content == _lastSyncedContent) {
      return;
    }

    final finalTitle = title.isEmpty ? '无标题' : title;

    _remoteSyncing = true;
    try {
      if (_isEffectivelyEditing) {
        await widget.noteProvider.updateNote(
          bid: _currentBid!,
          title: finalTitle,
          content: content,
        );
        _lastSyncedTitle = title;
        _lastSyncedContent = content;
        debugPrint('[SYNC] Remote sync successful');
      } else {
        // 还是新文档，内容刚输入，在这里创建
        final targetCollection =
            widget.collection ?? _collectionProvider?.defaultCollection;
        if (targetCollection != null) {
          final newNote = await widget.noteProvider.createNote(
            title: finalTitle,
            content: content,
            collectionBid: targetCollection.bid,
          );
          _newCreatedBid = newNote.bid;
          _lastSyncedTitle = title;
          _lastSyncedContent = content;
        }
      }
    } catch (e) {
      debugPrint('[SYNC] Remote sync failed: $e');
    } finally {
      _remoteSyncing = false;
      if (_remoteSyncQueued && mounted) {
        _remoteSyncQueued = false;
        unawaited(_syncRemote());
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _collectionProvider ??= context.read<CollectionProvider>();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottom = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .viewInsets
        .bottom;
    final nowVisible = bottom > 100;
    if (_keyboardVisible && !nowVisible) {
      if (mounted) FocusScope.of(context).unfocus();
    }
    _keyboardVisible = nowVisible;
  }

  Future<void> _refreshLatest() async {
    if (!mounted) return;
    final revision = _editRevision;

    // Step 1: 先从本地缓存读取，立即展示
    final store = NoteLocalStore.instance;
    final localBlock = await store.getBlock(widget.note!.bid);
    if (localBlock != null && mounted && revision == _editRevision) {
      final local = NoteModel.fromBlock(localBlock);
      _applyText(
        title: local.title.isEmpty ? null : local.title,
        content: local.content.isEmpty ? null : local.content,
        updateBaseline: true,
      );
      setState(() => _tags = List<String>.from(local.tags));
    }

    // Step 2: 后台请求远端，更新显示和本地缓存
    setState(() => _refreshing = true);
    try {
      final latest = await widget.noteProvider.refreshNote(widget.note!.bid);
      if (!mounted) return;
      if (revision == _editRevision) {
        _applyText(
          title: latest.title,
          content: latest.content,
          updateBaseline: true,
        );
        setState(() => _tags = List<String>.from(latest.tags));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _remoteSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_autoSave());
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _autoSave() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    // 检查是否有实质性内容修改（避免空文档或未修改文档的提交）
    if (title == _lastSyncedTitle && content == _lastSyncedContent) {
      return;
    }

    if (title.isEmpty && content.isEmpty) return;

    final targetCollection =
        widget.collection ?? _collectionProvider?.defaultCollection;

    if (_isEffectivelyEditing) {
      try {
        await widget.noteProvider.updateNote(
          bid: _currentBid!,
          title: title.isEmpty ? '无标题' : title,
          content: content,
        );
        _lastSyncedTitle = title;
        _lastSyncedContent = content;
      } catch (_) {}
    } else if (targetCollection != null) {
      try {
        await widget.noteProvider.createNote(
          title: title.isEmpty ? '无标题' : title,
          content: content,
          collectionBid: targetCollection.bid,
        );
        _lastSyncedTitle = title;
        _lastSyncedContent = content;
      } catch (_) {}
    }
  }

  void _onTitleSubmitted(String _) {
    _contentFocus.requestFocus();
    _contentCtrl.selection = const TextSelection.collapsed(offset: 0);
  }

  void _applyText({
    String? title,
    String? content,
    bool updateBaseline = false,
  }) {
    _applyingText = true;
    if (title != null && title != _titleCtrl.text) {
      _titleCtrl.text = title;
      _titleCtrl.selection = TextSelection.collapsed(offset: title.length);
    }
    if (content != null && content != _contentCtrl.text) {
      _contentCtrl.text = content;
      _contentCtrl.selection = TextSelection.collapsed(offset: content.length);
    }
    _applyingText = false;

    if (updateBaseline) {
      _lastSyncedTitle = _titleCtrl.text.trim();
      _lastSyncedContent = _contentCtrl.text.trim();
    }
  }

  void _mergeToTitle() {
    final sel = _contentCtrl.selection;
    if (sel.baseOffset != 0 || sel.extentOffset != 0) return;
    final content = _contentCtrl.text;
    final titleEnd = _titleCtrl.text.length;
    _titleCtrl.text = _titleCtrl.text + content;
    _titleCtrl.selection = TextSelection.collapsed(offset: titleEnd);
    _contentCtrl.text = '';
    _titleFocus.requestFocus();
  }

  Future<void> _showMoreMenu() async {
    final cs = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (widget.note != null) ...[
                // 复制 BID
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: const Text('复制 BID'),
                  onTap: () => Navigator.of(sheetCtx).pop('copy_bid'),
                ),
                // 添加标签
                ListTile(
                  leading: const Icon(Icons.label_outline_rounded),
                  title: const Text('添加标签'),
                  onTap: () => Navigator.of(sheetCtx).pop('add_tag'),
                ),
              ],
              // 删除
              if (widget.note != null)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                  title: Text('删除', style: TextStyle(color: cs.error)),
                  onTap: () => Navigator.of(sheetCtx).pop('delete'),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;

    switch (result) {
      case 'copy_bid':
        Clipboard.setData(ClipboardData(text: _currentBid!));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('BID 已复制'),
            duration: Duration(seconds: 2),
          ),
        );
      case 'add_tag':
        await _showAddTagDialog();
      case 'delete':
        await _confirmDelete();
    }
  }

  Future<void> _showAddTagDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('添加标签'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标签名称',
            hintText: '输入标签名称',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    if (!mounted) return;

    final tag = ctrl.text.trim();
    // 立刻显示新标签
    if (!_tags.contains(tag)) {
      setState(() => _tags = [..._tags, tag]);
    }

    // 后台提交，期间显示 loading
    setState(() => _saving = true);
    try {
      final refreshed = await widget.noteProvider.refreshNote(_currentBid!);
      final existing = List<String>.from(refreshed.tags);
      if (!existing.contains(tag)) existing.add(tag);
      await widget.noteProvider.updateNoteTags(
        bid: _currentBid!,
        tags: existing,
      );
      if (mounted) setState(() => _tags = existing);
    } catch (e) {
      // 提交失败，回滚本地显示
      if (mounted) {
        setState(() => _tags = _tags.where((t) => t != tag).toList());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('添加失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onLongPressTag(String tag) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '#$tag',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                title: Text('删除', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmDeleteTag(tag);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteTag(String tag) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除标签'),
        content: Text('确定要删除标签「#$tag」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteTag(tag);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTag(String tag) async {
    try {
      final refreshed = await widget.noteProvider.refreshNote(_currentBid!);
      final existing = List<String>.from(refreshed.tags)..remove(tag);
      await widget.noteProvider.updateNoteTags(
        bid: _currentBid!,
        tags: existing,
      );
      if (mounted) setState(() => _tags = existing);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (!_isEffectivelyEditing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除'),
        content: const Text('确定要删除这条备忘录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await widget.noteProvider.deleteNote(_currentBid!);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
        }
      }
    }
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    await _autoSave();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final bgColor = isDark ? AppPalette.nightInk : AppPalette.lightSurface;
    final controlColor = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.62)
        : cs.surfaceContainerLow.withValues(alpha: 0.72);
    final controlBorder = cs.outlineVariant.withValues(
      alpha: isDark ? 0.36 : 0.55,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _autoSave();
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // 可滚动内容区
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_titleFocus.hasFocus || _contentFocus.hasFocus) {
                    FocusScope.of(context).unfocus();
                  } else {
                    _contentFocus.requestFocus();
                  }
                },
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 72, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_tags.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _tags
                              .map(
                                (tag) => GestureDetector(
                                  onLongPress: () => _onLongPressTag(tag),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer.withValues(
                                        alpha: 0.6,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '#$tag',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _titleCtrl,
                        focusNode: _titleFocus,
                        autofocus: !_hasContent,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.next,
                        maxLines: 1,
                        onSubmitted: _onTitleSubmitted,
                      ),
                      KeyboardListener(
                        focusNode: FocusNode(),
                        onKeyEvent: (event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey ==
                                  LogicalKeyboardKey.backspace) {
                            _mergeToTitle();
                          }
                        },
                        child: TextField(
                          controller: _contentCtrl,
                          focusNode: _contentFocus,
                          style: const TextStyle(fontSize: 16, height: 1.65),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          maxLines: null,
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                      ),
                    ],
                  ),
                ),
              ),
              // 固定悬浮的返回按钮（玻璃效果）
              Positioned(
                top: 8,
                left: 16,
                child: GestureDetector(
                  onTap: _handleBack,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: controlColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: controlBorder, width: 0.5),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 固定悬浮的更多按钮（玻璃效果）
              Positioned(
                top: 8,
                right: 16,
                child: GestureDetector(
                  onTap: _showMoreMenu,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: controlColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: controlBorder, width: 0.5),
                        ),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 22,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_refreshing || _saving)
                Positioned(
                  top: 20,
                  left: 68,
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
