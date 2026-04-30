import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/note_collection.dart';
import '../providers/collection_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/note_provider.dart';
import '../services/note_service.dart';
import 'notes_list_screen.dart';
import 'note_editor_screen.dart';
import 'setup_screen.dart';
import 'settings_screen.dart';

class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  late final NoteProvider _noteProvider;

  @override
  void initState() {
    super.initState();
    _noteProvider = NoteProvider(context.read());
  }

  @override
  void dispose() {
    _noteProvider.dispose();
    super.dispose();
  }

  /// 点击 + 按钮弹出选项菜单
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
                subtitle: const Text('在节点上创建一个新集合'),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateCollectionDialog(context);
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
                subtitle: const Text('通过 BID 加入已有集合'),
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

  Future<void> _showCreateCollectionDialog(BuildContext context, {String? parentBid}) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('新建集合'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '集合名称',
            hintText: '输入集合名称',
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    if (!context.mounted) return;

    final connectionProvider = context.read<ConnectionProvider>();
    final collectionProvider = context.read<CollectionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = NoteService(connectionProvider);
      final collection = await service.createCollection(ctrl.text.trim(), parentBid: parentBid);
      await collectionProvider.addCollection(collection);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('创建失败：$e')));
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
          decoration: const InputDecoration(
            labelText: '集合 BID',
            hintText: '粘贴集合的 BID',
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('加入')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    if (!context.mounted) return;

    final connectionProvider = context.read<ConnectionProvider>();
    final collectionProvider = context.read<CollectionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = NoteService(connectionProvider);
      final collection = await service.fetchCollection(ctrl.text.trim());
      await collectionProvider.addCollection(collection);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('加入失败：$e')));
    }
  }

  /// 长按弹出操作菜单
  void _showActionSheet(BuildContext context, NoteCollection col) {
    final provider = context.read<CollectionProvider>();
    final isDefault = col.isDefault;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
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
                  child: Text(col.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: const Text('复制 BID'),
                  onTap: () {
                    Navigator.pop(context);
                    Clipboard.setData(ClipboardData(text: col.bid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('BID 已复制'), duration: Duration(seconds: 2)),
                    );
                  },
                ),
                if (!isDefault)
                  ListTile(
                    leading: const Icon(Icons.star_rounded, color: Color(0xFFFFCC00)),
                    title: const Text('设为默认集合'),
                    onTap: () {
                      Navigator.pop(context);
                      provider.setDefault(col.bid);
                    },
                  )
                else
                  ListTile(
                    leading: Icon(Icons.star_border_rounded, color: cs.onSurfaceVariant),
                    title: const Text('取消默认集合'),
                    onTap: () {
                      Navigator.pop(context);
                      provider.clearDefault();
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                  title: Text('移除集合', style: TextStyle(color: cs.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(context, col);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, NoteCollection col) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('移除集合'),
        content: Text('从列表中移除「${col.title}」？\n（不会删除远端数据）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              context.read<CollectionProvider>().removeCollection(col.bid);
            },
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  void _openCollection(BuildContext context, NoteCollection col) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => NotesListScreen(collection: col)));
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final colls = context.watch<CollectionProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    final defaultCol = colls.defaultCollection;
    final regularCols = colls.regularCollections;

    final canCreateNote = conn.hasActiveConnection && defaultCol != null;

    return Scaffold(
      backgroundColor: bgColor,
      floatingActionButton: canCreateNote
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NoteEditorScreen(
                    noteProvider: _noteProvider,
                    collection: defaultCol,
                  ),
                ),
              ),
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          SliverSafeArea(
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text(
                        '备忘录',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                      ),
                    ),
                    if (conn.hasActiveConnection)
                      IconButton(
                        icon: const Icon(Icons.create_new_folder_outlined),
                        tooltip: '新建/加入集合',
                        onPressed: () => _showAddMenu(context),
                      ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (!conn.hasActiveConnection)
            SliverFillRemaining(
              child: _NoConnectionView(
                onSetup: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupScreen())),
              ),
            )
          else if (colls.collections.isEmpty)
            SliverFillRemaining(
              child: _EmptyView(onAdd: () => _showAddMenu(context)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── 默认集合区域（始终显示）──
                  _SectionHeader(label: '默认集合'),
                  if (defaultCol != null)
                    _FolderGroup(
                      collections: [defaultCol],
                      isDefaultGroup: true,
                      onTap: (col) => _openCollection(context, col),
                      onLongPress: (col) => _showActionSheet(context, col),
                    )
                  else
                    _EmptyDefaultFolder(),
                  const SizedBox(height: 24),

                  // ── 我的集合 ──
                  if (regularCols.isNotEmpty) ...[
                    _SectionHeader(label: '我的集合'),
                    _FolderGroup(
                      collections: regularCols,
                      isDefaultGroup: false,
                      onTap: (col) => _openCollection(context, col),
                      onLongPress: (col) => _showActionSheet(context, col),
                    ),
                  ],

                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 子组件 ────────────────────────────────────────────────────

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

class _FolderGroup extends StatelessWidget {
  const _FolderGroup({
    required this.collections,
    required this.isDefaultGroup,
    required this.onTap,
    required this.onLongPress,
  });
  final List<NoteCollection> collections;
  final bool isDefaultGroup;
  final void Function(NoteCollection) onTap;
  final void Function(NoteCollection) onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardColor = cs.brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < collections.length; i++) ...[
            _FolderTile(
              collection: collections[i],
              isDefaultGroup: isDefaultGroup,
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

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.collection,
    required this.isDefaultGroup,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onLongPress,
  });
  final NoteCollection collection;
  final bool isDefaultGroup;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isDefaultGroup ? const Color(0xFFFFCC00) : const Color(0xFFFFCC00);

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
                color: iconColor,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                isDefaultGroup ? Icons.folder_special_rounded : Icons.folder_rounded,
                color: Colors.white,
                size: 17,
              ),
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
            if (isDefaultGroup)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.star_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _EmptyDefaultFolder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardColor = cs.brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(Icons.folder_special_outlined, color: cs.onSurfaceVariant.withValues(alpha: 0.5), size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '长按集合可设为默认集合',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoConnectionView extends StatelessWidget {
  const _NoConnectionView({required this.onSetup});
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('尚未配置节点', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('请先配置 Block 节点', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onSetup, icon: const Icon(Icons.settings_outlined), label: const Text('配置节点')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('还没有集合', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('点击右上角 + 加入一个集合', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('加入集合')),
          ],
        ),
      ),
    );
  }
}
