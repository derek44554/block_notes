import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/note_collection.dart';
import '../models/note_model.dart';
import '../models/note_list_item.dart';
import '../providers/note_provider.dart';
import '../providers/collection_provider.dart';
import '../providers/connection_provider.dart';
import '../services/note_service.dart';
import '../services/note_local_store.dart';
import 'note_editor_screen.dart';

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key, required this.collection});
  final NoteCollection collection;

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  late final NoteProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = NoteProvider(context.read());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.loadItems(widget.collection.bid);
      context.read<CollectionProvider>().setLastOpened(widget.collection.bid);
      // 同步完成后用最新 block 更新 CollectionProvider（含 link_tag 等字段）
      _provider.addListener(_onProviderUpdate);
    });
  }

  void _onProviderUpdate() {
    final block = _provider.latestCollectionBlock;
    if (block != null && !_provider.syncing) {
      final updated = NoteCollection.fromBlock(block).copyWith(
        isDefault: widget.collection.isDefault,
      );
      context.read<CollectionProvider>().addCollection(updated);
    }
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderUpdate);
    _provider.dispose();
    super.dispose();
  }

  Future<void> _openNote(NoteModel note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          note: note,
          collection: widget.collection,
          noteProvider: _provider,
        ),
      ),
    );
  }

  void _openSubCollection(NoteCollection col) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotesListScreen(collection: col)),
    );
  }

  Future<void> _openEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          collection: widget.collection,
          noteProvider: _provider,
        ),
      ),
    );
  }


  void _showInfoDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('添加链接标签'),
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
            onPressed: () async {
              final tag = ctrl.text.trim();
              if (tag.isEmpty) return;
              Navigator.pop(ctx);
              await _addLinkTag(tag);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Future<void> _addLinkTag(String tag) async {
    try {
      final service = NoteService(context.read<ConnectionProvider>());
      final block = _provider.latestCollectionBlock;
      final existing = block != null && block.data['link_tag'] is List
          ? List<String>.from((block.data['link_tag'] as List).whereType<String>())
          : List<String>.from(widget.collection.linkTags);
      if (!existing.contains(tag)) {
        existing.add(tag);
      }
      await service.updateCollectionLinkTags(widget.collection.bid, existing);
      await _provider.loadItems(widget.collection.bid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败：$e')));
      }
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
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(tag, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
        content: Text('确定要删除标签「$tag」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              _deleteLinkTag(tag);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLinkTag(String tag) async {
    try {
      final service = NoteService(context.read<ConnectionProvider>());
      final block = _provider.latestCollectionBlock;
      final existing = block != null && block.data['link_tag'] is List
          ? List<String>.from((block.data['link_tag'] as List).whereType<String>())
          : List<String>.from(widget.collection.linkTags);
      existing.remove(tag);
      await service.updateCollectionLinkTags(widget.collection.bid, existing);
      await _provider.loadItems(widget.collection.bid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  void _showAddMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCC00),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.create_new_folder_rounded, color: Colors.white, size: 20),
                ),
                title: const Text('新建集合'),
                subtitle: const Text('在当前集合下新建子集合'),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateSubCollectionDialog(context);
                },
              ),
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.folder_shared_rounded, color: Colors.white, size: 20),
                ),
                title: const Text('加入集合'),
                subtitle: const Text('将当前集合加入到另一个集合'),
                onTap: () {
                  Navigator.pop(context);
                  _showJoinCollectionDialog(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateSubCollectionDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('新建子集合'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '集合名称', hintText: '输入集合名称'),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    if (!context.mounted) return;
    try {
      final service = NoteService(context.read<ConnectionProvider>());
      await service.createCollection(ctrl.text.trim(), parentBid: widget.collection.bid);
      _provider.loadItems(widget.collection.bid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败：$e')));
      }
    }
  }

  Future<void> _showJoinCollectionDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('加入集合'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '目标集合 BID', hintText: '粘贴目标集合的 BID'),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('加入')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    if (!context.mounted) return;
    try {
      final service = NoteService(context.read<ConnectionProvider>());
      await service.joinCollection(
        targetBid: ctrl.text.trim(),
        currentCollectionBid: widget.collection.bid,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入集合')));
      }
      _provider.loadItems(widget.collection.bid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入失败：$e')));
      }
    }
  }

  /// 长按 item 弹出操作菜单
  void _showItemActions(NoteListItem item) {
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
              // 拖动条
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  item.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              // 复制 BID
              ListTile(
                leading: const Icon(Icons.fingerprint_rounded),
                title: const Text('复制 BID'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Clipboard.setData(ClipboardData(text: item.bid));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('BID 已复制'), duration: Duration(seconds: 2)),
                  );
                },
              ),
              // 选择集合（移动到另一个集合）
              ListTile(
                leading: const Icon(Icons.drive_file_move_rounded),
                title: const Text('移动'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showPickCollectionSheet(item);
                },
              ),
              // 删除
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                title: Text('删除', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmDelete(item);
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// 选择集合：把 item 的 link 改为目标集合
  Future<void> _showPickCollectionSheet(NoteListItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => _CollectionPickerSheet(
          scrollController: scrollCtrl,
          currentBid: item.bid,
          currentCollectionBid: widget.collection.bid,
          onPick: (col) async {
            Navigator.pop(sheetCtx);
            await _moveItemToCollection(item, col);
          },
        ),
      ),
    );
  }

  /// 将 item 移动到目标集合（修改 link 字段）
  Future<void> _moveItemToCollection(NoteListItem item, NoteCollection target) async {
    try {
      final service = NoteService(context.read<ConnectionProvider>());
      await service.moveItemToCollection(
        bid: item.bid,
        fromCollectionBid: widget.collection.bid,
        targetCollectionBid: target.bid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移动到「${target.title}」')),
        );
        _provider.loadItems(widget.collection.bid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移动失败：$e')));
      }
    }
  }

  Future<void> _confirmDelete(NoteListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除'),
        content: Text('确定要删除「${item.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await _provider.deleteNote(item.bid);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  /// 集合区 + 文档区分开渲染
  Widget _buildList(BuildContext context, ColorScheme cs) {
    final collections = _provider.items.whereType<NoteListItemCollection>().toList();
    final notes = _provider.items.whereType<NoteListItemNote>().toList();
    final widgets = <Widget>[];

    if (collections.isNotEmpty) {
      widgets.add(const _SectionHeader(label: '集合'));
      widgets.add(_CollectionGroup(
        collections: collections.map((e) => e.collection).toList(),
        onTap: _openSubCollection,
        onLongPress: (col) => _showItemActions(NoteListItemCollection(col)),
      ));
      widgets.add(const SizedBox(height: 24));
    }

    if (notes.isNotEmpty) {
      widgets.add(const _SectionHeader(label: '备忘录'));
      for (var i = 0; i < notes.length; i++) {
        final note = notes[i].note;
        final item = notes[i];
        widgets.add(_NoteRow(
          note: note,
          isFirst: i == 0,
          isLast: i == notes.length - 1,
          onTap: () => _openNote(note),
          onDelete: () => _showItemActions(item),
        ));
      }
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      sliver: SliverList(delegate: SliverChildListDelegate(widgets)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = cs.brightness == Brightness.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) context.read<CollectionProvider>().setLastOpened(null);
      },
      child: ListenableBuilder(
        listenable: _provider,
        builder: (context, _) {
          return Scaffold(
            backgroundColor: bgColor,
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: bgColor,
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  toolbarHeight: 44,
                  titleSpacing: 0,
                  title: _provider.syncing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        )
                      : const SizedBox.shrink(),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.label_outline_rounded),
                      tooltip: '集合信息',
                      onPressed: () => _showInfoDialog(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      tooltip: '新建/加入集合',
                      onPressed: () => _showAddMenu(context),
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.collection.title,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                        ),
                        // link_tag 显示
                        _LinkTagsRow(provider: _provider, collection: widget.collection, collectionBid: widget.collection.bid, onLongPressTag: _onLongPressTag),
                      ],
                    ),
                  ),
                ),
                if (_provider.isLoading)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else if (_provider.state == NoteLoadState.error)
                  SliverFillRemaining(
                    child: _ErrorView(
                      error: _provider.error ?? '',
                      onRetry: () => _provider.loadItems(widget.collection.bid),
                    ),
                  )
                else if (_provider.items.isEmpty)
                  const SliverFillRemaining(child: _EmptyView())
                else
                  _buildList(context, cs),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: _openEditor,
              child: const Icon(Icons.edit_outlined),
            ),
          );
        },
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── 子集合卡片组 ──────────────────────────────────────────────

class _CollectionGroup extends StatelessWidget {
  const _CollectionGroup({
    required this.collections,
    required this.onTap,
    required this.onLongPress,
  });
  final List<NoteCollection> collections;
  final void Function(NoteCollection) onTap;
  final void Function(NoteCollection) onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardColor = cs.brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white;

    return Container(
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          for (var i = 0; i < collections.length; i++) ...[
            _CollectionTile(
              collection: collections[i],
              isFirst: i == 0,
              isLast: i == collections.length - 1,
              onTap: () => onTap(collections[i]),
              onLongPress: () => onLongPress(collections[i]),
            ),
            if (i < collections.length - 1)
              Divider(height: 1, indent: 52, color: cs.outlineVariant.withValues(alpha: 0.4)),
          ],
        ],
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.collection,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onLongPress,
  });
  final NoteCollection collection;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(12) : Radius.zero,
        bottom: isLast ? const Radius.circular(12) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFFFCC00),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.folder_rounded, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                collection.title,
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ── 文档行（无箭头）──────────────────────────────────────────

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onDelete,
  });
  final NoteModel note;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardColor = cs.brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(12) : Radius.zero,
          bottom: isLast ? const Radius.circular(12) : Radius.zero,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            onLongPress: onDelete,
            borderRadius: BorderRadius.vertical(
              top: isFirst ? const Radius.circular(12) : Radius.zero,
              bottom: isLast ? const Radius.circular(12) : Radius.zero,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        note.formattedDate,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                      if (note.preview.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note.preview,
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!isLast)
            Divider(height: 1, indent: 16, color: cs.outlineVariant.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

// ── 空/错误状态 ───────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('加载失败', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_alt_outlined, size: 56,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('还没有内容', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('点击右下角按钮新建',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

// ── 链接标签行 ────────────────────────────────────────────────

class _LinkTagsRow extends StatelessWidget {
  const _LinkTagsRow({
    required this.provider,
    required this.collection,
    required this.collectionBid,
    this.onLongPressTag,
  });
  final NoteProvider provider;
  final NoteCollection collection;
  final String collectionBid;
  final void Function(String tag)? onLongPressTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final block = provider.latestCollectionBlock;
    final tags = block != null
        ? (block.data['link_tag'] is List
            ? List<String>.from((block.data['link_tag'] as List).whereType<String>().where((t) => t.trim().isNotEmpty))
            : <String>[])
        : collection.linkTags;

    if (tags.isEmpty) return const SizedBox.shrink();

    final activeTag = provider.activeTag;

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '链接标签',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((tag) {
              final isActive = activeTag == tag;
              return GestureDetector(
                onTap: () => provider.filterByTag(collectionBid, tag),
                onLongPress: () => onLongPressTag?.call(tag),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? cs.primary
                        : cs.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 13,
                      color: isActive ? cs.onPrimary : cs.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── 集合选择器（树形，本地数据）────────────────────────────────

const _collectionModelId = '1635e536a5a331a283f9da56b7b51774';

class _CollectionPickerSheet extends StatefulWidget {
  const _CollectionPickerSheet({
    required this.scrollController,
    required this.currentBid,
    required this.currentCollectionBid,
    required this.onPick,
  });
  final ScrollController scrollController;
  final String currentBid;           // 被移动的 item 的 bid（不能选自己）
  final String currentCollectionBid; // 当前所在集合（标注"当前"）
  final void Function(NoteCollection) onPick;

  @override
  State<_CollectionPickerSheet> createState() => _CollectionPickerSheetState();
}

class _CollectionPickerSheetState extends State<_CollectionPickerSheet> {
  // 展开状态：bid → 是否展开
  final Map<String, bool> _expanded = {};
  // 子集合缓存：bid → List<NoteCollection>
  final Map<String, List<NoteCollection>> _children = {};

  List<NoteCollection> get _roots =>
      context.read<CollectionProvider>().collections;

  /// 从本地缓存读取某集合下的子集合列表
  Future<List<NoteCollection>> _loadChildren(String bid) async {
    if (_children.containsKey(bid)) return _children[bid]!;
    final store = NoteLocalStore.instance;
    final bids = await store.getBids(bid);
    if (bids.isEmpty) return [];
    final blocks = await store.getBlocks(bids);
    final cols = bids
        .where((b) => blocks.containsKey(b))
        .where((b) => blocks[b]!.data['model'] == _collectionModelId)
        .map((b) => NoteCollection.fromBlock(blocks[b]!))
        .toList();
    _children[bid] = cols;
    return cols;
  }

  /// 检查某集合本地是否有子集合（用于决定是否显示展开箭头）
  Future<bool> _hasChildren(String bid) async {
    final kids = await _loadChildren(bid);
    return kids.isNotEmpty;
  }

  Future<void> _toggle(String bid) async {
    final kids = await _loadChildren(bid);
    setState(() {
      if (_expanded[bid] == true) {
        _expanded[bid] = false;
      } else {
        _expanded[bid] = true;
        _children[bid] = kids;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final roots = _roots;

    return Column(
      children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            '移动',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: roots.length,
            itemBuilder: (_, i) => _CollectionPickerNode(
              collection: roots[i],
              depth: 0,
              currentBid: widget.currentBid,
              currentCollectionBid: widget.currentCollectionBid,
              expanded: _expanded,
              children: _children,
              onToggle: _toggle,
              hasChildren: _hasChildren,
              onPick: widget.onPick,
            ),
          ),
        ),
      ],
    );
  }
}

/// 单个集合节点（递归渲染子集合）
class _CollectionPickerNode extends StatelessWidget {
  const _CollectionPickerNode({
    required this.collection,
    required this.depth,
    required this.currentBid,
    required this.currentCollectionBid,
    required this.expanded,
    required this.children,
    required this.onToggle,
    required this.hasChildren,
    required this.onPick,
  });

  final NoteCollection collection;
  final int depth;
  final String currentBid;
  final String currentCollectionBid;
  final Map<String, bool> expanded;
  final Map<String, List<NoteCollection>> children;
  final Future<void> Function(String) onToggle;
  final Future<bool> Function(String) hasChildren;
  final void Function(NoteCollection) onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bid = collection.bid;
    final isCurrent = bid == currentCollectionBid;
    final isSelf = bid == currentBid;
    final isExpanded = expanded[bid] == true;
    final kids = children[bid] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: (isCurrent || isSelf) ? null : () => onPick(collection),
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0 + depth * 20.0,
              right: 8,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: (isCurrent || isSelf)
                        ? cs.onSurfaceVariant.withValues(alpha: 0.15)
                        : const Color(0xFFFFCC00),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: (isCurrent || isSelf) ? cs.onSurfaceVariant : Colors.white,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection.title,
                        style: TextStyle(
                          fontSize: 15,
                          color: (isCurrent || isSelf)
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isCurrent)
                        Text('当前集合', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                // 展开/收起按钮（FutureBuilder 检查是否有子集合）
                FutureBuilder<bool>(
                  future: hasChildren(bid),
                  builder: (_, snap) {
                    if (snap.data != true) return const SizedBox(width: 36);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onToggle(bid),
                      child: SizedBox(
                        width: 36, height: 36,
                        child: Center(
                          child: AnimatedRotation(
                            turns: isExpanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        // 子集合（展开时显示）
        if (isExpanded)
          for (final child in kids)
            _CollectionPickerNode(
              collection: child,
              depth: depth + 1,
              currentBid: currentBid,
              currentCollectionBid: currentCollectionBid,
              expanded: expanded,
              children: children,
              onToggle: onToggle,
              hasChildren: hasChildren,
              onPick: onPick,
            ),
        if (depth == 0)
          Divider(height: 1, indent: 16, color: cs.outlineVariant.withValues(alpha: 0.3)),
      ],
    );
  }
}
