import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:block_flutter/block_flutter.dart';
import '../models/note_model.dart';
import '../models/note_list_item.dart';
import '../services/note_service.dart';
import '../providers/connection_provider.dart';

enum NoteLoadState { idle, loading, loaded, error }

class NoteProvider extends ChangeNotifier {
  NoteProvider(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  List<NoteListItem> _items = [];
  NoteLoadState _state = NoteLoadState.idle;
  String? _error;
  String? _currentCollectionBid;
  bool _syncing = false;
  BlockModel? _latestCollectionBlock;
  String? _activeTag; // 当前激活的 link_tag 筛选
  Map<String, int> _itemOrderIndexes = {};
  int _loadToken = 0;

  List<NoteListItem> get items => List.unmodifiable(_items);
  NoteLoadState get state => _state;
  String? get error => _error;
  bool get isLoading => _state == NoteLoadState.loading;
  bool get syncing => _syncing;
  BlockModel? get latestCollectionBlock => _latestCollectionBlock;
  String? get activeTag => _activeTag;

  NoteService get _service => NoteService(_connectionProvider);

  Map<String, int> _indexBids(List<String> bids) => {
    for (var i = 0; i < bids.length; i++) bids[i]: i,
  };

  /// 加载集合内容（任意层级集合通用）：
  ///   1. 立即展示本地缓存
  ///   2. 后台同步最新数据
  Future<void> loadItems(String collectionBid) async {
    final token = ++_loadToken;
    _currentCollectionBid = collectionBid;
    _activeTag = null;
    _error = null;
    _itemOrderIndexes = {};
    _items = [];
    _state = NoteLoadState.loading;
    _syncing = false;
    notifyListeners();

    final service = _service;

    bool isCurrentLoad() =>
        token == _loadToken && _currentCollectionBid == collectionBid;

    // Step 1: 本地缓存先展示，空集合也要立刻清空旧列表
    final localBids = await service.getLocalBids(collectionBid);
    if (!isCurrentLoad()) return;
    _itemOrderIndexes = _indexBids(localBids);
    _items = await service.getLocalItems(
      localBids,
      collectionBid: collectionBid,
    );
    if (!isCurrentLoad()) return;
    _state = NoteLoadState.loaded;
    _syncing = true;
    notifyListeners();

    // Step 2: 后台同步（先刷新集合自身，再同步外链）
    final collectionFuture = service
        .refreshCollection(collectionBid)
        .then<BlockModel?>((block) => block)
        .catchError((_) => null);
    try {
      final freshBids = await service.syncCollection(collectionBid);
      if (!isCurrentLoad()) return;
      final latestBlock = await collectionFuture;
      if (!isCurrentLoad()) return;
      if (latestBlock != null) _latestCollectionBlock = latestBlock;
      _itemOrderIndexes = _indexBids(freshBids);
      _items = await service.getLocalItems(
        freshBids,
        collectionBid: collectionBid,
      );
      if (!isCurrentLoad()) return;
      _state = NoteLoadState.loaded;
    } catch (e) {
      if (!isCurrentLoad()) return;
      final latestBlock = await collectionFuture;
      if (!isCurrentLoad()) return;
      if (latestBlock != null) _latestCollectionBlock = latestBlock;
      if (_items.isEmpty) {
        _error = e.toString();
        _state = NoteLoadState.error;
      }
    } finally {
      if (isCurrentLoad()) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  /// 按 link_tag 筛选：传入 tag 激活筛选，传入已激活的 tag 则取消筛选
  Future<void> filterByTag(String collectionBid, String tag) async {
    if (_activeTag == tag) {
      _activeTag = null;
      await loadItems(collectionBid);
      return;
    }
    _activeTag = tag;
    final token = ++_loadToken;
    _currentCollectionBid = collectionBid;

    bool isCurrentFilter() =>
        token == _loadToken &&
        _currentCollectionBid == collectionBid &&
        _activeTag == tag;

    final service = _service;

    // Step 1: 立即用本地缓存筛选，瞬间展示
    final localBids = await service.getLocalBidsByTag(collectionBid, tag);
    if (!isCurrentFilter()) return;
    _itemOrderIndexes = _indexBids(localBids);
    _items = await service.getLocalItems(
      localBids,
      collectionBid: collectionBid,
    );
    if (!isCurrentFilter()) return;
    _state = NoteLoadState.loaded;
    _syncing = true;
    notifyListeners();

    // Step 2: 后台异步请求服务器，不阻塞当前帧
    unawaited(_syncTagInBackground(service, collectionBid, tag, token));
  }

  Future<void> _syncTagInBackground(
    NoteService service,
    String collectionBid,
    String tag,
    int token,
  ) async {
    bool isCurrentFilter() =>
        token == _loadToken &&
        _currentCollectionBid == collectionBid &&
        _activeTag == tag;

    try {
      final freshBids = await service.syncCollectionByTag(collectionBid, tag);
      // 只有 tag 没变才更新
      if (isCurrentFilter()) {
        _itemOrderIndexes = _indexBids(freshBids);
        _items = await service.getLocalItems(
          freshBids,
          collectionBid: collectionBid,
        );
        _state = NoteLoadState.loaded;
      }
    } catch (_) {
      // 后台失败不影响已展示的本地结果
    } finally {
      if (isCurrentFilter()) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  Future<NoteModel> createNote({
    required String title,
    required String content,
    required String collectionBid,
  }) async {
    final note = await _service.createNote(
      title: title,
      content: content,
      collectionBid: collectionBid,
    );

    // 1. 立即加入内存列表并通知 UI
    if (_currentCollectionBid == collectionBid && _activeTag == null) {
      _itemOrderIndexes = {
        note.bid: -1,
        for (final entry in _itemOrderIndexes.entries)
          entry.key: entry.value + 1,
      };
      _items = sortNoteListItems([
        NoteListItemNote(note),
        ..._items.where((item) => item.bid != note.bid),
      ], originalIndexes: _itemOrderIndexes);
      _state = NoteLoadState.loaded;
      notifyListeners();
    }

    // 2. 注意：这里我们不需要立即调用 loadItems(collectionBid)，
    // 因为这会发起网络同步并覆盖掉我们刚加进去的本地项。
    // 我们只需要在后台静默同步一次即可，不更新 UI
    unawaited(
      _service.syncCollection(collectionBid).catchError((_) => <String>[]),
    );

    return note;
  }

  Future<void> updateNote({
    required String bid,
    required String title,
    required String content,
    DateTime? updatedAt,
    String? collectionBid,
    bool refreshItems = true,
  }) async {
    final targetCollectionBid = collectionBid ?? _currentCollectionBid;
    final targetActiveTag = _activeTag;
    final targetLoadToken = _loadToken;
    await _service.updateNote(
      bid: bid,
      title: title,
      content: content,
      updatedAt: updatedAt,
    );
    if (!refreshItems) return;
    if (targetCollectionBid == null ||
        _currentCollectionBid != targetCollectionBid ||
        _activeTag != targetActiveTag ||
        _loadToken != targetLoadToken) {
      return;
    }
    await _updateItemsFromLocal(
      collectionBid: targetCollectionBid,
      activeTag: targetActiveTag,
      loadToken: targetLoadToken,
    );
  }

  /// 仅更新本地缓存并通知 UI（用于实时编辑实时显示）
  Future<void> updateNoteLocal({
    required String bid,
    required String title,
    required String content,
    DateTime? updatedAt,
  }) async {
    await _service.updateNoteLocal(
      bid: bid,
      title: title,
      content: content,
      updatedAt: updatedAt,
    );

    if (_updateNoteInMemory(
      bid: bid,
      title: title,
      content: content,
      updatedAt: updatedAt,
    )) {
      return;
    }

    // 如果没在当前列表（可能是在搜索或其他情况），则尝试完整更新
    await _updateItemsFromLocal();
  }

  void updateNotePreview({
    required String bid,
    required String title,
    required String content,
    required DateTime updatedAt,
  }) {
    _updateNoteInMemory(
      bid: bid,
      title: title,
      content: content,
      updatedAt: updatedAt,
    );
  }

  bool _updateNoteInMemory({
    required String bid,
    required String title,
    required String content,
    DateTime? updatedAt,
  }) {
    bool found = false;
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.bid == bid && item is NoteListItemNote) {
        if (updatedAt != null && item.note.updatedAt.isAfter(updatedAt)) {
          found = true;
          break;
        }
        _items[i] = item.copyWith(
          title: title,
          summary: content,
          updatedAt: updatedAt,
        );
        found = true;
        break;
      }
    }

    if (found) {
      _items = sortNoteListItems(
        _items,
        originalIndexes: _itemOrderIndexes,
      );
      notifyListeners();
    }
    return found;
  }

  bool _replaceNoteInMemory(NoteModel note) {
    bool found = false;
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.bid == note.bid && item is NoteListItemNote) {
        if (item.note.updatedAt.isAfter(note.updatedAt)) {
          return true;
        }
        _items[i] = NoteListItemNote(note);
        found = true;
        break;
      }
    }

    if (found) {
      _items = sortNoteListItems(
        _items,
        originalIndexes: _itemOrderIndexes,
      );
      notifyListeners();
    }
    return found;
  }

  Future<void> _updateItemsFromLocal({
    String? collectionBid,
    String? activeTag,
    int? loadToken,
  }) async {
    final targetCollectionBid = collectionBid ?? _currentCollectionBid;
    if (targetCollectionBid == null) return;
    final targetActiveTag = collectionBid == null ? _activeTag : activeTag;
    final targetLoadToken = loadToken ?? _loadToken;

    final bids = targetActiveTag == null
        ? await _service.getLocalBids(targetCollectionBid)
        : await _service.getLocalBidsByTag(targetCollectionBid, targetActiveTag);
    final items = await _service.getLocalItems(
      bids,
      collectionBid: targetCollectionBid,
    );
    if (_currentCollectionBid != targetCollectionBid ||
        _activeTag != targetActiveTag ||
        _loadToken != targetLoadToken) {
      return;
    }

    _itemOrderIndexes = _indexBids(bids);
    _items = items;
    notifyListeners();
  }

  Future<void> updateNoteTags({
    required String bid,
    required List<String> tags,
  }) async {
    await _service.updateNoteTags(bid: bid, tags: tags);
  }

  Future<void> updateNotePinned({
    required String bid,
    required bool isPinned,
    String? collectionBid,
  }) async {
    final targetCollectionBid = collectionBid ?? _currentCollectionBid;
    final targetActiveTag = _activeTag;
    final targetLoadToken = _loadToken;
    await _service.updateNotePinned(bid: bid, isPinned: isPinned);
    if (targetCollectionBid == null ||
        _currentCollectionBid != targetCollectionBid ||
        _activeTag != targetActiveTag ||
        _loadToken != targetLoadToken) {
      return;
    }
    await _updateItemsFromLocal(
      collectionBid: targetCollectionBid,
      activeTag: targetActiveTag,
      loadToken: targetLoadToken,
    );
  }

  Future<void> deleteNote(String bid) async {
    await _service.deleteNote(bid, collectionBid: _currentCollectionBid);
    _itemOrderIndexes = {
      for (final entry in _itemOrderIndexes.entries)
        if (entry.key != bid) entry.key: entry.value,
    };
    _items = _items.where((i) => i.bid != bid).toList();
    notifyListeners();
  }

  /// 刷新单个文档的本地缓存，返回最新 NoteModel
  Future<NoteModel> refreshNote(String bid) async {
    final note = await _service.refreshNote(bid);
    _replaceNoteInMemory(note);
    return note;
  }

  void clear() {
    _loadToken++;
    _items = [];
    _itemOrderIndexes = {};
    _state = NoteLoadState.idle;
    _error = null;
    _currentCollectionBid = null;
    _syncing = false;
    notifyListeners();
  }
}
