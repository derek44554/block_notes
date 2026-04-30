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
  int _loadToken = 0;

  List<NoteListItem> get items => List.unmodifiable(_items);
  NoteLoadState get state => _state;
  String? get error => _error;
  bool get isLoading => _state == NoteLoadState.loading;
  bool get syncing => _syncing;
  BlockModel? get latestCollectionBlock => _latestCollectionBlock;
  String? get activeTag => _activeTag;

  NoteService get _service => NoteService(_connectionProvider);

  /// 加载集合内容（任意层级集合通用）：
  ///   1. 立即展示本地缓存
  ///   2. 后台同步最新数据
  Future<void> loadItems(String collectionBid) async {
    final token = ++_loadToken;
    _currentCollectionBid = collectionBid;
    _activeTag = null;
    _error = null;

    final service = _service;

    bool isCurrentLoad() =>
        token == _loadToken && _currentCollectionBid == collectionBid;

    // Step 1: 本地缓存先展示，空集合也要立刻清空旧列表
    final localBids = await service.getLocalBids(collectionBid);
    if (!isCurrentLoad()) return;
    _items = await service.getLocalItems(localBids);
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
      _items = await service.getLocalItems(freshBids);
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
    _items = await service.getLocalItems(localBids);
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
        _items = await service.getLocalItems(freshBids);
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
      _items = [
        NoteListItemNote(note),
        ..._items.where((item) => item.bid != note.bid),
      ];
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
  }) async {
    await _service.updateNote(bid: bid, title: title, content: content);
    await _updateItemsFromLocal();
  }

  /// 仅更新本地缓存并通知 UI（用于实时编辑实时显示）
  Future<void> updateNoteLocal({
    required String bid,
    required String title,
    required String content,
  }) async {
    await _service.updateNoteLocal(bid: bid, title: title, content: content);

    // 优化：直接更新内存中的 _items，避免重新读取整个列表
    bool found = false;
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.bid == bid && item is NoteListItemNote) {
        _items[i] = item.copyWith(title: title, summary: content);
        found = true;
        break;
      }
    }

    if (found) {
      notifyListeners();
    } else {
      // 如果没在当前列表（可能是在搜索或其他情况），则尝试完整更新
      await _updateItemsFromLocal();
    }
  }

  Future<void> _updateItemsFromLocal() async {
    if (_currentCollectionBid != null) {
      final bids = _activeTag == null
          ? await _service.getLocalBids(_currentCollectionBid!)
          : await _service.getLocalBidsByTag(
              _currentCollectionBid!,
              _activeTag!,
            );
      _items = await _service.getLocalItems(bids);
      notifyListeners();
    }
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
  }) async {
    await _service.updateNotePinned(bid: bid, isPinned: isPinned);
    await _updateItemsFromLocal();
  }

  Future<void> deleteNote(String bid) async {
    await _service.deleteNote(bid, collectionBid: _currentCollectionBid);
    _items = _items.where((i) => i.bid != bid).toList();
    notifyListeners();
  }

  /// 刷新单个文档的本地缓存，返回最新 NoteModel
  Future<NoteModel> refreshNote(String bid) => _service.refreshNote(bid);

  void clear() {
    _loadToken++;
    _items = [];
    _state = NoteLoadState.idle;
    _error = null;
    _currentCollectionBid = null;
    _syncing = false;
    notifyListeners();
  }
}
