import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/note_collection.dart';
import '../models/note_list_item.dart';
import '../models/note_model.dart';
import '../providers/collection_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/note_provider.dart';
import '../services/note_local_store.dart';
import '../services/note_service.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

class MacNotesScreen extends StatefulWidget {
  const MacNotesScreen({super.key, this.initialCollection});

  final NoteCollection? initialCollection;

  @override
  State<MacNotesScreen> createState() => _MacNotesScreenState();
}

class _MacNotesScreenState extends State<MacNotesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();

  NoteProvider? _noteProvider;
  NoteCollection? _selectedCollection;
  String? _selectedNoteBid;
  NoteModel? _selectedNote;
  List<String> _selectedTags = [];
  Timer? _localSaveTimer;
  Timer? _remoteSaveTimer;
  bool _bootstrapped = false;
  bool _loadingNote = false;
  bool _syncingEditor = false;
  bool _remoteSyncQueued = false;
  bool _applyingEditorText = false;
  int _collectionLoadToken = 0;
  int _noteLoadToken = 0;
  int _editorRevision = 0;
  String _lastRemoteTitle = '';
  String _lastRemoteContent = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _titleCtrl.addListener(_onEditorChanged);
    _contentCtrl.addListener(_onEditorChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<NoteProvider>();
    if (_noteProvider != provider) {
      _noteProvider?.removeListener(_onItemsChanged);
      _noteProvider = provider..addListener(_onItemsChanged);
    }
    if (!_bootstrapped) {
      _bootstrapped = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _bootstrapSelection(),
      );
    }
  }

  @override
  void dispose() {
    _noteProvider?.removeListener(_onItemsChanged);
    _localSaveTimer?.cancel();
    _remoteSaveTimer?.cancel();
    unawaited(_syncEditorRemote(updateUi: false));
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _bootstrapSelection() {
    if (!mounted) return;
    final collections = context.read<CollectionProvider>().collections;
    if (collections.isEmpty) return;

    final initialBid = widget.initialCollection?.bid;
    final lastBid = context.read<CollectionProvider>().lastOpenedBid;
    final collection =
        _collectionByBid(collections, initialBid) ??
        _collectionByBid(collections, lastBid) ??
        context.read<CollectionProvider>().defaultCollection ??
        collections.first;
    _selectCollection(collection);
  }

  NoteCollection? _collectionByBid(
    List<NoteCollection> collections,
    String? bid,
  ) {
    if (bid == null) return null;
    for (final collection in collections) {
      if (collection.bid == bid) return collection;
    }
    return null;
  }

  Future<void> _selectCollection(NoteCollection collection) async {
    if (_selectedCollection?.bid == collection.bid) return;
    await _syncEditorRemote();
    if (!mounted) return;
    final token = ++_collectionLoadToken;
    setState(() {
      _selectedCollection = collection;
      _selectedNoteBid = null;
      _selectedNote = null;
      _selectedTags = [];
      _setEditorText('', '');
    });
    await context.read<CollectionProvider>().setLastOpened(collection.bid);
    await _noteProvider?.loadItems(collection.bid);
    if (!mounted || token != _collectionLoadToken) return;
    _selectFirstVisibleNote();
  }

  void _onItemsChanged() {
    if (!mounted || _selectedCollection == null) return;

    final provider = _noteProvider;
    if (provider == null || provider.state != NoteLoadState.loaded) return;

    final selectedBid = _selectedNoteBid;
    if (selectedBid != null) {
      for (final item in provider.items) {
        if (item is NoteListItemNote && item.note.bid == selectedBid) {
          _selectedNote = item.note;
          if (!_titleFocus.hasFocus && !_contentFocus.hasFocus) {
            _lastRemoteTitle = item.note.title;
            _lastRemoteContent = item.note.content;
          }
          setState(() {});
          return;
        }
      }
    }

    _selectFirstVisibleNote();
  }

  void _selectFirstVisibleNote() {
    final firstNote = _visibleItems()
        .whereType<NoteListItemNote>()
        .map((item) => item.note)
        .firstOrNull;
    if (firstNote == null) {
      setState(() {
        _selectedNoteBid = null;
        _selectedNote = null;
        _selectedTags = [];
        _setEditorText('', '');
      });
      return;
    }
    unawaited(_selectNote(firstNote, focusTitle: false));
  }

  Future<void> _selectNote(NoteModel note, {bool focusTitle = false}) async {
    if (_selectedNoteBid == note.bid && !_loadingNote) return;
    await _syncEditorRemote();
    final token = ++_noteLoadToken;
    setState(() {
      _selectedNoteBid = note.bid;
      _selectedNote = note;
      _selectedTags = List<String>.from(note.tags);
      _loadingNote = true;
      _setEditorText(note.title, note.content);
      _lastRemoteTitle = note.title;
      _lastRemoteContent = note.content;
    });
    final revision = _editorRevision;

    try {
      final latest = await _noteProvider?.refreshNote(note.bid);
      if (!mounted || token != _noteLoadToken || latest == null) return;
      if (revision != _editorRevision) return;
      setState(() {
        _selectedNote = latest;
        _selectedTags = List<String>.from(latest.tags);
        _setEditorText(latest.title, latest.content);
        _lastRemoteTitle = latest.title;
        _lastRemoteContent = latest.content;
      });
    } catch (_) {
    } finally {
      if (mounted && token == _noteLoadToken) {
        setState(() => _loadingNote = false);
        if (focusTitle) _titleFocus.requestFocus();
      }
    }
  }

  void _setEditorText(String title, String content) {
    _applyingEditorText = true;
    _titleCtrl.text = title;
    _contentCtrl.text = content;
    _titleCtrl.selection = TextSelection.collapsed(
      offset: _titleCtrl.text.length,
    );
    _contentCtrl.selection = TextSelection.collapsed(
      offset: _contentCtrl.text.length,
    );
    _applyingEditorText = false;
  }

  void _onEditorChanged() {
    if (_applyingEditorText || _selectedNoteBid == null) return;
    _editorRevision++;
    _localSaveTimer?.cancel();
    _localSaveTimer = Timer(
      const Duration(milliseconds: 350),
      _saveEditorLocal,
    );
    _remoteSaveTimer?.cancel();
    _remoteSaveTimer = Timer(const Duration(seconds: 3), _syncEditorRemote);
  }

  Future<void> _saveEditorLocal() async {
    final bid = _selectedNoteBid;
    if (bid == null) return;
    final title = _normalizedTitle;
    final content = _contentCtrl.text;
    await _noteProvider?.updateNoteLocal(
      bid: bid,
      title: title,
      content: content,
    );
    if (!mounted || _selectedNoteBid != bid) return;
    setState(() {
      _selectedNote =
          (_selectedNote ??
                  NoteModel(
                    bid: bid,
                    title: title,
                    content: content,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ))
              .copyWith(
                title: title,
                content: content,
                updatedAt: DateTime.now(),
              );
    });
  }

  Future<void> _syncEditorRemote({bool updateUi = true}) async {
    final bid = _selectedNoteBid;
    if (bid == null) return;
    if (_syncingEditor) {
      _remoteSyncQueued = true;
      return;
    }
    final title = _normalizedTitle;
    final content = _contentCtrl.text;
    if (title == _lastRemoteTitle && content == _lastRemoteContent) return;

    _syncingEditor = true;
    if (updateUi && mounted) setState(() {});
    try {
      await _noteProvider?.updateNote(bid: bid, title: title, content: content);
      if (_selectedNoteBid == bid) {
        _lastRemoteTitle = title;
        _lastRemoteContent = content;
      }
    } catch (_) {
    } finally {
      _syncingEditor = false;
      if (updateUi && mounted) setState(() {});
      if (_remoteSyncQueued && mounted) {
        _remoteSyncQueued = false;
        unawaited(_syncEditorRemote(updateUi: updateUi));
      }
    }
  }

  String get _normalizedTitle {
    final title = _titleCtrl.text.trim();
    return title.isEmpty ? '无标题' : title;
  }

  Future<void> _createNote() async {
    final collection = _selectedCollection;
    if (collection == null) return;
    await _syncEditorRemote();
    final note = await _noteProvider?.createNote(
      title: '无标题',
      content: '',
      collectionBid: collection.bid,
    );
    if (!mounted || note == null) return;
    await _selectNote(note, focusTitle: true);
  }

  Future<void> _deleteSelectedNote() async {
    final bid = _selectedNoteBid;
    if (bid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除备忘录'),
        content: const Text('确定要删除当前备忘录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _noteProvider?.deleteNote(bid);
    if (!mounted) return;
    setState(() {
      _selectedNoteBid = null;
      _selectedNote = null;
      _selectedTags = [];
      _setEditorText('', '');
    });
    _selectFirstVisibleNote();
  }

  Future<void> _deleteNote(NoteModel note) async {
    await _selectNote(note);
    await _deleteSelectedNote();
  }

  Future<void> _copyNoteBid(NoteModel note) async {
    await Clipboard.setData(ClipboardData(text: note.bid));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('BID 已复制'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _moveNote(NoteModel note) async {
    final current = _selectedCollection;
    if (current == null) return;
    final targets = context
        .read<CollectionProvider>()
        .collections
        .where((c) => c.bid != current.bid)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可移动到的集合')));
      return;
    }

    final target = await showDialog<NoteCollection>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('移动到'),
        children: [
          for (final target in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, target),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(target.title, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;

    try {
      await NoteService(
        context.read<ConnectionProvider>(),
      ).moveItemToCollection(
        bid: note.bid,
        fromCollectionBid: current.bid,
        targetCollectionBid: target.bid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已移动到「${target.title}」')));
      await _noteProvider?.loadItems(current.bid);
      if (_selectedNoteBid == note.bid) {
        setState(() {
          _selectedNoteBid = null;
          _selectedNote = null;
          _selectedTags = [];
          _setEditorText('', '');
        });
        _selectFirstVisibleNote();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('移动失败：$e')));
    }
  }

  Future<void> _showCreateCollectionDialog({String? parentBid}) async {
    var input = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建集合'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: '集合名称'),
          onChanged: (value) => input = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    try {
      final collection = await NoteService(
        context.read<ConnectionProvider>(),
      ).createCollection(name, parentBid: parentBid);
      if (!mounted) return;
      if (parentBid == null) {
        await context.read<CollectionProvider>().addCollection(collection);
        if (!mounted) return;
        await _selectCollection(collection);
      } else {
        await _noteProvider?.loadItems(parentBid);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建失败：$e')));
    }
  }

  Future<void> _showJoinCollectionDialog({String? currentCollectionBid}) async {
    var input = '';
    final bid = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('加入集合'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(
            labelText: currentCollectionBid == null ? '集合 BID' : '目标集合 BID',
          ),
          onChanged: (value) => input = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.trim()),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (bid == null || bid.isEmpty || !mounted) return;

    try {
      final service = NoteService(context.read<ConnectionProvider>());
      if (currentCollectionBid == null) {
        final collection = await service.fetchCollection(bid);
        if (!mounted) return;
        await context.read<CollectionProvider>().addCollection(collection);
        if (!mounted) return;
        await _selectCollection(collection);
      } else {
        await service.joinCollection(
          targetBid: bid,
          currentCollectionBid: currentCollectionBid,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入集合')));
        await _noteProvider?.loadItems(currentCollectionBid);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入失败：$e')));
    }
  }

  Future<void> _copyCollectionBid(NoteCollection collection) async {
    await Clipboard.setData(ClipboardData(text: collection.bid));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('BID 已复制'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _moveCollection(NoteCollection collection) async {
    final targets = context
        .read<CollectionProvider>()
        .collections
        .where((c) => c.bid != collection.bid)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可移动到的集合')));
      return;
    }

    final target = await showDialog<NoteCollection>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('移动到'),
        children: [
          for (final target in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, target),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(target.title, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;

    try {
      await NoteService(context.read<ConnectionProvider>()).joinCollection(
        targetBid: target.bid,
        currentCollectionBid: collection.bid,
      );
      if (!mounted) return;
      await context.read<CollectionProvider>().removeCollection(collection.bid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已移动到「${target.title}」')));
      if (_selectedCollection?.bid == collection.bid) {
        await _selectCollection(target);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('移动失败：$e')));
    }
  }

  Future<void> _removeCollection(NoteCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除集合'),
        content: Text('从列表中移除「${collection.title}」？\n不会删除远端数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<CollectionProvider>().removeCollection(collection.bid);
    if (!mounted) return;
    final collections = context.read<CollectionProvider>().collections;
    if (_selectedCollection?.bid == collection.bid) {
      if (collections.isEmpty) {
        setState(() {
          _selectedCollection = null;
          _selectedNoteBid = null;
          _selectedNote = null;
          _setEditorText('', '');
        });
      } else {
        await _selectCollection(collections.first);
      }
    }
  }

  List<NoteListItem> _visibleItems() {
    final provider = _noteProvider;
    if (provider == null) return const [];
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return provider.items;
    return provider.items.where((item) {
      final title = item.title.toLowerCase();
      if (title.contains(query)) return true;
      if (item is NoteListItemNote) {
        return item.note.content.toLowerCase().contains(query);
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final collections = context.watch<CollectionProvider>().collections;
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    if (conn.hasActiveConnection &&
        collections.isNotEmpty &&
        _selectedCollection == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _bootstrapSelection(),
      );
    }

    return Scaffold(
      backgroundColor: _MacPalette.window(isDark),
      body: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            SizedBox(
              width: 220,
              child: _MacSidebar(
                collections: collections,
                selectedBid: _selectedCollection?.bid,
                onSelect: _selectCollection,
                onCreateCollection: () => _showCreateCollectionDialog(),
                onJoinCollection: _showJoinCollectionDialog,
                onOpenSettings: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                onCopyCollectionBid: _copyCollectionBid,
                onCreateChildCollection: (collection) =>
                    _showCreateCollectionDialog(parentBid: collection.bid),
                onJoinCurrentCollection: (collection) =>
                    _showJoinCollectionDialog(
                      currentCollectionBid: collection.bid,
                    ),
                onMoveCollection: _moveCollection,
                onRemoveCollection: _removeCollection,
              ),
            ),
            _MacDivider(isDark: isDark),
            SizedBox(
              width: 280,
              child: _MacArticleList(
                collection: _selectedCollection,
                items: _visibleItems(),
                isLoading: _noteProvider?.isLoading ?? false,
                isSyncing: _noteProvider?.syncing ?? false,
                selectedBid: _selectedNoteBid,
                hasConnection: conn.hasActiveConnection,
                hasCollections: collections.isNotEmpty,
                onSelectNote: _selectNote,
                onCreateNote: _createNote,
                onCopyNoteBid: _copyNoteBid,
                onMoveNote: _moveNote,
                onDeleteNote: _deleteNote,
                onSetup: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SetupScreen()),
                ),
              ),
            ),
            _MacDivider(isDark: isDark),
            Expanded(
              child: _MacEditorPane(
                selectedNote: _selectedNote,
                titleController: _titleCtrl,
                contentController: _contentCtrl,
                titleFocus: _titleFocus,
                contentFocus: _contentFocus,
                tags: _selectedTags,
                loading: _loadingNote,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacSidebar extends StatefulWidget {
  const _MacSidebar({
    required this.collections,
    required this.selectedBid,
    required this.onSelect,
    required this.onCreateCollection,
    required this.onJoinCollection,
    required this.onOpenSettings,
    required this.onCopyCollectionBid,
    required this.onCreateChildCollection,
    required this.onJoinCurrentCollection,
    required this.onMoveCollection,
    required this.onRemoveCollection,
  });

  final List<NoteCollection> collections;
  final String? selectedBid;
  final ValueChanged<NoteCollection> onSelect;
  final VoidCallback onCreateCollection;
  final VoidCallback onJoinCollection;
  final VoidCallback onOpenSettings;
  final ValueChanged<NoteCollection> onCopyCollectionBid;
  final ValueChanged<NoteCollection> onCreateChildCollection;
  final ValueChanged<NoteCollection> onJoinCurrentCollection;
  final ValueChanged<NoteCollection> onMoveCollection;
  final ValueChanged<NoteCollection> onRemoveCollection;

  @override
  State<_MacSidebar> createState() => _MacSidebarState();
}

class _MacSidebarState extends State<_MacSidebar> {
  final Map<String, bool> _expanded = {};

  Future<List<NoteCollection>> _loadChildCollections(String bid) async {
    final bids = await NoteLocalStore.instance.getBids(bid);
    if (bids.isEmpty) return const [];
    final blocks = await NoteLocalStore.instance.getBlocks(bids);
    final children = <NoteCollection>[];
    for (final childBid in bids) {
      final block = blocks[childBid];
      if (block == null) continue;
      final item = NoteListItem.fromBlock(block);
      if (item is NoteListItemCollection) {
        children.add(item.collection);
      }
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final defaults = widget.collections.where((c) => c.isDefault).toList();
    final regular = widget.collections.where((c) => !c.isDefault).toList();

    return Container(
      color: _MacPalette.sidebar(isDark),
      child: Column(
        children: [
          _SidebarToolbar(onOpenSettings: widget.onOpenSettings),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              children: [
                _SidebarSectionLabel(
                  label: '集合',
                  onContextMenu: _showRootContextMenu,
                ),
                if (defaults.isNotEmpty)
                  for (final collection in defaults)
                    _buildCollectionNode(collection, 0, null),
                if (regular.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final collection in regular)
                    _buildCollectionNode(collection, 0, null),
                ],
                if (widget.collections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
                    child: Text(
                      '还没有集合',
                      style: TextStyle(
                        fontSize: 13,
                        color: _MacPalette.secondaryText(isDark),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionNode(
    NoteCollection collection,
    int depth,
    String? parentBid,
  ) {
    return FutureBuilder<List<NoteCollection>>(
      future: _loadChildCollections(collection.bid),
      builder: (context, snapshot) {
        final children = snapshot.data ?? const <NoteCollection>[];
        final hasChildren = children.isNotEmpty;
        final expanded = _expanded[collection.bid] == true;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SidebarCollectionTile(
              collection: collection,
              selected: collection.bid == widget.selectedBid,
              depth: depth,
              hasChildren: hasChildren,
              isExpanded: expanded,
              isTopLevel: depth == 0,
              onToggle: hasChildren
                  ? () => setState(() {
                      _expanded[collection.bid] = !expanded;
                    })
                  : null,
              onTap: () => widget.onSelect(collection),
              onCopyBid: () => widget.onCopyCollectionBid(collection),
              onCreateChild: () => widget.onCreateChildCollection(collection),
              onJoinCurrent: () => widget.onJoinCurrentCollection(collection),
              onMove: () => widget.onMoveCollection(collection),
              onRemove: () => depth == 0
                  ? widget.onRemoveCollection(collection)
                  : _deleteChildCollection(collection, parentBid!),
            ),
            if (expanded)
              for (final child in children)
                _buildCollectionNode(child, depth + 1, collection.bid),
          ],
        );
      },
    );
  }

  Future<void> _deleteChildCollection(
    NoteCollection collection,
    String parentBid,
  ) async {
    try {
      await NoteService(
        context.read<ConnectionProvider>(),
      ).deleteNote(collection.bid);
      final bids = await NoteLocalStore.instance.getBids(parentBid);
      await NoteLocalStore.instance.saveBids(
        parentBid,
        bids.where((bid) => bid != collection.bid).toList(),
      );
      if (!mounted) return;
      if (widget.selectedBid == collection.bid) {
        final parentBlock = await NoteLocalStore.instance.getBlock(parentBid);
        if (parentBlock != null && mounted) {
          widget.onSelect(NoteCollection.fromBlock(parentBlock));
        }
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('集合已删除')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  Future<void> _showRootContextMenu(Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'create', child: Text('新建集合')),
        PopupMenuItem(value: 'join', child: Text('加入集合')),
      ],
    );
    if (!mounted) return;

    switch (value) {
      case 'create':
        widget.onCreateCollection();
      case 'join':
        widget.onJoinCollection();
    }
  }
}

class _SidebarToolbar extends StatelessWidget {
  const _SidebarToolbar({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          const SizedBox(width: 72),
          const Spacer(),
          _MacIconButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            onPressed: onOpenSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label, this.onContextMenu});

  final String label;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onContextMenu == null
          ? null
          : (details) => onContextMenu!(details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _MacPalette.secondaryText(isDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarCollectionTile extends StatelessWidget {
  const _SidebarCollectionTile({
    required this.collection,
    required this.selected,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.isTopLevel,
    required this.onToggle,
    required this.onTap,
    required this.onCopyBid,
    required this.onCreateChild,
    required this.onJoinCurrent,
    required this.onMove,
    required this.onRemove,
  });

  final NoteCollection collection;
  final bool selected;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final bool isTopLevel;
  final VoidCallback? onToggle;
  final VoidCallback onTap;
  final VoidCallback onCopyBid;
  final VoidCallback onCreateChild;
  final VoidCallback onJoinCurrent;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final textColor = selected
        ? _MacPalette.accent(isDark)
        : _MacPalette.primaryText(isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? _MacPalette.selection(isDark) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            onLongPress: onRemove,
            child: Padding(
              padding: EdgeInsets.fromLTRB(4.0 + depth * 14.0, 6, 8, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    child: hasChildren
                        ? InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: onToggle,
                            child: AnimatedRotation(
                              turns: isExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 140),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 13,
                                color: _MacPalette.secondaryText(isDark),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 1),
                  Icon(Icons.folder_outlined, size: 17, color: textColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      collection.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                  FutureBuilder<int>(
                    future: NoteLocalStore.instance
                        .getBids(collection.bid)
                        .then((bids) => bids.length),
                    builder: (context, snap) {
                      final count = snap.data;
                      if (count == null || count == 0) {
                        return const SizedBox(width: 4);
                      }
                      return Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? textColor
                              : _MacPalette.tertiaryText(isDark),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('复制 BID')),
        const PopupMenuItem(value: 'create_child', child: Text('新建集合')),
        const PopupMenuItem(value: 'join_current', child: Text('加入集合')),
        const PopupMenuItem(value: 'move', child: Text('移动')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'remove', child: Text(isTopLevel ? '移除' : '删除')),
      ],
    );

    switch (value) {
      case 'copy':
        onCopyBid();
      case 'create_child':
        onCreateChild();
      case 'join_current':
        onJoinCurrent();
      case 'move':
        onMove();
      case 'remove':
        onRemove();
    }
  }
}

class _MacArticleList extends StatelessWidget {
  const _MacArticleList({
    required this.collection,
    required this.items,
    required this.isLoading,
    required this.isSyncing,
    required this.selectedBid,
    required this.hasConnection,
    required this.hasCollections,
    required this.onSelectNote,
    required this.onCreateNote,
    required this.onCopyNoteBid,
    required this.onMoveNote,
    required this.onDeleteNote,
    required this.onSetup,
  });

  final NoteCollection? collection;
  final List<NoteListItem> items;
  final bool isLoading;
  final bool isSyncing;
  final String? selectedBid;
  final bool hasConnection;
  final bool hasCollections;
  final ValueChanged<NoteModel> onSelectNote;
  final VoidCallback onCreateNote;
  final ValueChanged<NoteModel> onCopyNoteBid;
  final ValueChanged<NoteModel> onMoveNote;
  final ValueChanged<NoteModel> onDeleteNote;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final notes = items.whereType<NoteListItemNote>().toList();

    return Container(
      color: _MacPalette.listPane(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ArticleListHeader(
            collection: collection,
            count: notes.length,
            syncing: isSyncing,
            onCreateNote: onCreateNote,
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (!hasConnection) {
                  return _PaneState(
                    icon: Icons.cloud_off_outlined,
                    title: '尚未配置节点',
                    actionLabel: '配置节点',
                    onAction: onSetup,
                  );
                }
                if (!hasCollections) {
                  return _PaneState(
                    icon: Icons.folder_open_outlined,
                    title: '还没有集合',
                  );
                }
                if (isLoading && notes.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                if (notes.isEmpty) {
                  return _PaneState(
                    icon: Icons.note_add_outlined,
                    title: '没有备忘录',
                    actionLabel: '新建备忘录',
                    onAction: onCreateNote,
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  children: [
                    for (var i = 0; i < notes.length; i++)
                      _NoteListTile(
                        note: notes[i].note,
                        selected: notes[i].note.bid == selectedBid,
                        hideBottomDivider:
                            notes[i].note.bid == selectedBid ||
                            (i + 1 < notes.length &&
                                notes[i + 1].note.bid == selectedBid),
                        collectionTitle: collection?.title ?? '',
                        onTap: () => onSelectNote(notes[i].note),
                        onCopyBid: () => onCopyNoteBid(notes[i].note),
                        onMove: () => onMoveNote(notes[i].note),
                        onDelete: () => onDeleteNote(notes[i].note),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleListHeader extends StatelessWidget {
  const _ArticleListHeader({
    required this.collection,
    required this.count,
    required this.syncing,
    required this.onCreateNote,
  });

  final NoteCollection? collection;
  final int count;
  final bool syncing;
  final VoidCallback onCreateNote;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    return Container(
      height: 74,
      padding: const EdgeInsets.fromLTRB(22, 12, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection?.title ?? '备忘录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _MacPalette.primaryText(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$count 个备忘录',
                      style: TextStyle(
                        fontSize: 12,
                        color: _MacPalette.secondaryText(isDark),
                      ),
                    ),
                    if (syncing) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _MacPalette.secondaryText(isDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MacIconButton(
                  icon: Icons.edit_square,
                  tooltip: '新建备忘录',
                  size: 18,
                  buttonSize: 32,
                  onPressed: collection == null ? null : onCreateNote,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.selected,
    required this.hideBottomDivider,
    required this.collectionTitle,
    required this.onTap,
    required this.onCopyBid,
    required this.onMove,
    required this.onDelete,
  });

  final NoteModel note;
  final bool selected;
  final bool hideBottomDivider;
  final String collectionTitle;
  final VoidCallback onTap;
  final VoidCallback onCopyBid;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final primaryText = selected
        ? _MacPalette.selectedText(isDark)
        : _MacPalette.primaryText(isDark);
    final secondaryText = selected
        ? _MacPalette.selectedSecondaryText(isDark)
        : _MacPalette.secondaryText(isDark);
    final tertiaryText = selected
        ? _MacPalette.selectedSecondaryText(isDark)
        : _MacPalette.tertiaryText(isDark);

    return Material(
      color: selected ? _MacPalette.noteSelection(isDark) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: selected
              ? Colors.transparent
              : _MacPalette.noteHover(isDark),
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          focusColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: hideBottomDivider
                ? null
                : BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: _MacPalette.divider(isDark)),
                    ),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: primaryText,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      _relativeDate(note.updatedAt),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        note.preview.isEmpty ? '无更多文本' : note.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 14, color: tertiaryText),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        collectionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: secondaryText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('复制 BID')),
        PopupMenuItem(value: 'move', child: Text('移动')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );

    switch (value) {
      case 'copy':
        onCopyBid();
      case 'move':
        onMove();
      case 'delete':
        onDelete();
    }
  }
}

class _MacEditorPane extends StatelessWidget {
  const _MacEditorPane({
    required this.selectedNote,
    required this.titleController,
    required this.contentController,
    required this.titleFocus,
    required this.contentFocus,
    required this.tags,
    required this.loading,
  });

  final NoteModel? selectedNote;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final FocusNode titleFocus;
  final FocusNode contentFocus;
  final List<String> tags;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    return Container(
      color: _MacPalette.editor(isDark),
      child: selectedNote == null
          ? _PaneState(icon: Icons.sticky_note_2_outlined, title: '选择一篇备忘录')
          : Stack(
              children: [
                Positioned.fill(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _focusContentEnd,
                      child: ColoredBox(
                        color: _MacPalette.editor(isDark),
                        child: Scrollbar(
                          thickness: 1.5,
                          radius: const Radius.circular(999),
                          thumbVisibility: false,
                          trackVisibility: false,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 18, 28, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: titleController,
                                  focusNode: titleFocus,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: _MacPalette.primaryText(isDark),
                                    height: 1.18,
                                  ),
                                  cursorWidth: 1.2,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      contentFocus.requestFocus(),
                                ),
                                if (tags.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: tags
                                        .map((tag) => _TagChip(label: tag))
                                        .toList(),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Focus(
                                  onKeyEvent: (node, event) {
                                    if (event is KeyDownEvent &&
                                        event.logicalKey ==
                                            LogicalKeyboardKey.backspace &&
                                        _isAtContentStart()) {
                                      _mergeContentToTitle();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TextField(
                                    controller: contentController,
                                    focusNode: contentFocus,
                                    minLines: null,
                                    maxLines: null,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.55,
                                      color: _MacPalette.primaryText(isDark),
                                    ),
                                    cursorWidth: 1.2,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (loading)
                  Positioned(
                    top: 18,
                    right: 24,
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _MacPalette.secondaryText(isDark),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  bool _isAtContentStart() {
    final selection = contentController.selection;
    return selection.isCollapsed && selection.baseOffset == 0;
  }

  void _mergeContentToTitle() {
    final titleLength = titleController.text.length;
    titleController.text = titleController.text + contentController.text;
    titleController.selection = TextSelection.collapsed(offset: titleLength);
    contentController.clear();
    titleFocus.requestFocus();
  }

  void _focusContentEnd() {
    contentFocus.requestFocus();
    contentController.selection = TextSelection.collapsed(
      offset: contentController.text.length,
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$label',
        style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
      ),
    );
  }
}

class _PaneState extends StatelessWidget {
  const _PaneState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: _MacPalette.tertiaryText(isDark)),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _MacPalette.secondaryText(isDark),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MacIconButton extends StatelessWidget {
  const _MacIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 20,
    this.buttonSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double? buttonSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: buttonSize == null
            ? null
            : BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
        padding: EdgeInsets.zero,
        iconSize: size,
        splashRadius: 18,
        color: _MacPalette.icon(isDark),
        disabledColor: _MacPalette.tertiaryText(isDark).withValues(alpha: 0.45),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _MacDivider extends StatelessWidget {
  const _MacDivider({required this.isDark}) : horizontal = false;

  final bool isDark;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return Container(height: 1, color: _MacPalette.divider(isDark));
    }
    return Container(width: 1, color: _MacPalette.divider(isDark));
  }
}

class _MacPalette {
  const _MacPalette._();

  static Color window(bool dark) =>
      dark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F4F1);
  static Color sidebar(bool dark) =>
      dark ? const Color(0xFF242424) : const Color(0xFFEDEBE7);
  static Color listPane(bool dark) =>
      dark ? const Color(0xFF1F1F1F) : const Color(0xFFF7F5F0);
  static Color editor(bool dark) =>
      dark ? const Color(0xFF1C1C1C) : const Color(0xFFFFFCF6);
  static Color divider(bool dark) =>
      dark ? const Color(0xFF343434) : const Color(0xFFD8D4CC);
  static Color selection(bool dark) =>
      dark ? const Color(0xFF3A3A3A) : const Color(0xFFE7DFD2);
  static Color noteSelection(bool dark) =>
      dark ? const Color(0xFFB98511) : const Color(0xFFD89500);
  static Color noteHover(bool dark) =>
      dark ? const Color(0xFF2B2B2B) : const Color(0xFFEDE7DB);
  static Color accent(bool dark) =>
      dark ? const Color(0xFFD1A332) : const Color(0xFF9A6A00);
  static Color primaryText(bool dark) =>
      dark ? const Color(0xFFE9E9E9) : const Color(0xFF26231E);
  static Color secondaryText(bool dark) =>
      dark ? const Color(0xFFB8B8B8) : const Color(0xFF6F6A61);
  static Color tertiaryText(bool dark) =>
      dark ? const Color(0xFF8F8F8F) : const Color(0xFF9B948A);
  static Color icon(bool dark) =>
      dark ? const Color(0xFFB8B8B8) : const Color(0xFF6E675D);
  static Color selectedText(bool dark) => Colors.white;
  static Color selectedSecondaryText(bool dark) =>
      Colors.white.withValues(alpha: 0.78);
}

String _relativeDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = today.difference(target).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 7) return '星期${_weekday(date.weekday)}';
  return '${date.year}/${date.month}/${date.day}';
}

String _weekday(int weekday) {
  const labels = ['一', '二', '三', '四', '五', '六', '日'];
  return labels[(weekday - 1).clamp(0, labels.length - 1)];
}
