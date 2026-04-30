import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:block_flutter/block_flutter.dart';
import '../providers/connection_provider.dart';
import '../models/note_model.dart';
import '../models/note_collection.dart';
import '../models/note_list_item.dart';
import 'note_local_store.dart';

const _noteModelId = '93b133932057a254cc15d0f09c91ca98';
const _collectionModelId = '1635e536a5a331a283f9da56b7b51774';
const _batchSize = 50;
const _maxParallelBlockFetches = 3;

String _blockTimestampNow() => DateTime.now().toIso8601String();
String _blockTimestamp(DateTime? time) =>
    (time ?? DateTime.now()).toIso8601String();

class NoteService {
  NoteService(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  ConnectionModel get _connection {
    final c = _connectionProvider.activeConnection;
    if (c == null) throw StateError('No active connection available.');
    return c;
  }

  BlockApi get _api => BlockApi(connection: _connection);
  static Future<void>? _pendingFlush;

  String get _nodeBid {
    final nodeData = _connection.nodeData;
    if (nodeData == null) throw StateError('Node data not available.');
    // /node/node 响应结构: { data: { bid: '...' } } 或直接 { bid: '...' }
    final inner = nodeData['data'];
    final searchMap = inner is Map<String, dynamic> ? inner : nodeData;
    final bid =
        searchMap['bid'] as String? ??
        searchMap['sender'] as String? ??
        searchMap['node_bid'] as String?;
    if (bid == null || bid.isEmpty) {
      throw StateError('Node BID not found in nodeData: $nodeData');
    }
    return bid;
  }

  final _store = NoteLocalStore.instance;

  // ── 集合验证 ───────────────────────────────────────────────

  Future<NoteCollection> fetchCollection(String bid) async {
    final response = await _api.getBlock(bid: bid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final block = BlockModel(data: blockData);
    await _store.saveBlock(bid, block);
    return NoteCollection.fromBlock(block);
  }

  /// 在节点上新建一个集合 block，返回创建好的 NoteCollection
  /// [parentBid] 不为空时，新集合的 link 里放父集合 BID
  Future<NoteCollection> createCollection(
    String name, {
    String? parentBid,
  }) async {
    final nodeBid = _nodeBid;
    final bid = generateBidV2(nodeBid);
    final now = _blockTimestampNow();
    final data = <String, dynamic>{
      'bid': bid,
      'name': name,
      'model': _collectionModelId,
      'node_bid': nodeBid,
      'permission_level': 0,
      'tag': <String>[],
      'link': parentBid != null ? [parentBid] : <String>[],
      'add_time': now,
      'update_time': now,
    };
    await _api.saveBlock(data: data, receiverBid: nodeBid);
    final block = BlockModel(data: data);
    await _store.saveBlock(bid, block);
    if (parentBid != null) {
      await _store.addBidToCollection(parentBid, bid);
    }
    return NoteCollection.fromBlock(block);
  }

  /// 加入集合：把 [currentCollectionBid] 加入到 [targetBid] block 的 link 字段里
  Future<void> joinCollection({
    required String targetBid,
    required String currentCollectionBid,
  }) async {
    // 获取目标 block 最新数据
    final response = await _api.getBlock(bid: targetBid);
    final raw = response['data'];
    if (raw == null || raw is! Map<String, dynamic>) {
      throw Exception('未找到 BID 对应的集合');
    }
    final updatedData = Map<String, dynamic>.from(raw);
    final links = updatedData['link'] is List
        ? List<String>.from((updatedData['link'] as List).whereType<String>())
        : <String>[];
    if (links.contains(currentCollectionBid)) {
      throw Exception('该集合已在链接列表中');
    }
    links.add(currentCollectionBid);
    updatedData['link'] = links;
    updatedData['bid'] = targetBid;
    updatedData['update_time'] = _blockTimestampNow();
    await _api.saveBlock(data: updatedData);
    await _store.saveBlock(targetBid, BlockModel(data: updatedData));
    await _store.addBidToCollection(targetBid, currentCollectionBid);
  }

  // ── 核心同步 ───────────────────────────────────────────────

  /// 拉取集合自身最新 block 并更新本地缓存，返回最新 BlockModel
  Future<BlockModel> refreshCollection(String collectionBid) async {
    final response = await _api.getBlock(bid: collectionBid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final block = BlockModel(data: blockData);
    await _store.saveBlock(collectionBid, block);
    return block;
  }

  /// 同步外链 BID 列表并持久化（合并本地新增项，防止索引延迟导致本地项消失）
  Future<List<String>> syncCollection(String collectionBid) async {
    unawaited(flushPendingWrites());
    final freshBids = await _syncBids(collectionBid);
    final localBids = await _store.getBids(collectionBid);
    final pendingBids = (await _store.getPendingWriteBids()).toSet();
    final optimisticBids = await _store.getOptimisticBids(collectionBid);
    final mergedBids = _mergeFreshWithPreservedLocal(
      freshBids: freshBids,
      localBids: localBids,
      preserveBids: {...pendingBids, ...optimisticBids},
    );

    await _store.clearOptimisticBids(collectionBid, freshBids);
    await _store.saveBids(collectionBid, mergedBids);
    return mergedBids;
  }

  /// 按 link_tag 筛选同步外链 BID（同样应用合并策略）
  Future<List<String>> syncCollectionByTag(
    String collectionBid,
    String tag,
  ) async {
    unawaited(flushPendingWrites());
    final freshBids = await _syncBids(collectionBid, tag: tag);
    final localBids = await _getLocalBidsMatchingTag(collectionBid, tag);
    final pendingBids = (await _store.getPendingWriteBids()).toSet();
    final optimisticBids = await _store.getOptimisticBids(collectionBid);
    final mergedBids = _mergeFreshWithPreservedLocal(
      freshBids: freshBids,
      localBids: localBids,
      preserveBids: {...pendingBids, ...optimisticBids},
    );

    await _store.saveBidsForTag(collectionBid, tag, mergedBids);
    return mergedBids;
  }

  Future<List<String>> _syncBids(String collectionBid, {String? tag}) async {
    // 1. 拉取 BID 列表
    final freshBids = await _api.getBidsByTargets(
      bids: [collectionBid],
      order: 'desc',
      tag: tag,
    );

    // 2. 找出本地没有详情的 BID
    final missing = await _store.getMissingBids(freshBids);

    // 3. 分批拉取缺失的 block 详情
    await _fetchMissingBlocks(missing);

    return freshBids;
  }

  /// 从本地缓存按 link_tag 筛选 BID 列表
  Future<List<String>> getLocalBidsByTag(
    String collectionBid,
    String tag,
  ) async {
    final allLocalBids = await _store.getBids(collectionBid);
    final localMatches = await _getLocalBidsMatchingTag(collectionBid, tag);
    if (allLocalBids.isEmpty) {
      return _store.getBidsForTag(collectionBid, tag);
    }
    return localMatches;
  }

  /// 从本地读取集合的 BID 列表
  Future<List<String>> getLocalBids(String collectionBid) =>
      _store.getBids(collectionBid);

  /// 从本地读取 BID 列表对应的列表项（文档或子集合），集合在前，备忘录按更新时间倒序。
  Future<List<NoteListItem>> getLocalItems(List<String> bids) async {
    final blocks = await _store.getBlocks(bids);
    final items = <NoteListItem>[];
    final originalIndexes = <String, int>{
      for (var i = 0; i < bids.length; i++) bids[i]: i,
    };
    for (final bid in bids) {
      final block = blocks[bid];
      if (block == null) continue;
      items.add(NoteListItem.fromBlock(block));
    }
    return sortNoteListItems(items, originalIndexes: originalIndexes);
  }

  DateTime? _blockChangedAt(BlockModel block) =>
      block.getDateTime('update_time') ??
      block.getDateTime('updated_at') ??
      block.getDateTime('add_time') ??
      block.getDateTime('created_at');

  bool _blockIsNewerThan(BlockModel? block, DateTime? time) {
    if (block == null || time == null) return false;
    final localTime = _blockChangedAt(block);
    return localTime != null && localTime.isAfter(time);
  }

  Future<void> _fetchMissingBlocks(List<String> missing) async {
    final chunks = <List<String>>[];
    for (var i = 0; i < missing.length; i += _batchSize) {
      final end = i + _batchSize > missing.length
          ? missing.length
          : i + _batchSize;
      chunks.add(missing.sublist(i, end));
    }

    for (var i = 0; i < chunks.length; i += _maxParallelBlockFetches) {
      final end = i + _maxParallelBlockFetches > chunks.length
          ? chunks.length
          : i + _maxParallelBlockFetches;
      await Future.wait(chunks.sublist(i, end).map(_fetchBlockBatch));
    }
  }

  Future<void> _fetchBlockBatch(List<String> batch) async {
    if (batch.isEmpty) return;
    try {
      final response = await _api.getMultipleBlocks(bids: batch);
      final models = _parseBlocksResponse(response);
      if (models.isNotEmpty) {
        await _store.saveBlocks(models);
      }
    } catch (_) {
      // 单个批次失败不应中断整个集合加载，后续同步还会重试。
    }
  }

  List<BlockModel> _parseBlocksResponse(Map<String, dynamic> response) {
    final data = response['data'] ?? response;
    final Object? rawBlocks = switch (data) {
      {'blocks': final blocks} => blocks,
      {'data': final blocks} => blocks,
      List() => data,
      _ => null,
    };
    if (rawBlocks is! List) return const [];
    return rawBlocks
        .whereType<Map<String, dynamic>>()
        .map((data) => BlockModel(data: data))
        .toList();
  }

  Future<List<String>> _getLocalBidsMatchingTag(
    String collectionBid,
    String tag,
  ) async {
    final bids = await _store.getBids(collectionBid);
    if (bids.isEmpty) return const [];
    final blocks = await _store.getBlocks(bids);
    return bids.where((bid) {
      final block = blocks[bid];
      return block != null && _blockHasLinkTag(block, tag);
    }).toList();
  }

  bool _blockHasLinkTag(BlockModel block, String tag) {
    final normalizedTag = tag.trim();
    if (normalizedTag.isEmpty) return false;
    final raw = block.data['link_tag'];
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((value) => value.trim())
          .contains(normalizedTag);
    }
    if (raw is String) return raw.trim() == normalizedTag;
    return false;
  }

  List<String> _mergeFreshWithPreservedLocal({
    required List<String> freshBids,
    required List<String> localBids,
    required Set<String> preserveBids,
  }) {
    final merged = List<String>.from(freshBids);
    final freshSet = Set<String>.from(freshBids);
    for (final bid in localBids.reversed) {
      if (!freshSet.contains(bid) && preserveBids.contains(bid)) {
        merged.insert(0, bid);
      }
    }
    return merged;
  }

  // ── 单个 block 刷新（进入文档时调用）─────────────────────

  Future<void> flushPendingWrites() {
    final running = _pendingFlush;
    if (running != null) return running;
    final future = _flushPendingWrites();
    _pendingFlush = future.whenComplete(() => _pendingFlush = null);
    return _pendingFlush!;
  }

  Future<void> _flushPendingWrites() async {
    final pendingBids = await _store.getPendingWriteBids();
    for (final bid in pendingBids) {
      final block = await _store.getBlock(bid);
      if (block == null) {
        await _store.clearPendingWrite(bid);
        continue;
      }
      try {
        await _api.saveBlock(data: block.data);
        await _store.clearPendingWrite(bid);
      } catch (e) {
        debugPrint('[NoteService] Pending write retry failed for $bid: $e');
        return;
      }
    }
  }

  /// 拉取单个 block 最新数据，更新本地缓存，返回最新 NoteModel
  Future<NoteModel> refreshNote(String bid) async {
    final localBlock = await _store.getBlock(bid);
    final pendingBids = await _store.getPendingWriteBids();
    if (pendingBids.contains(bid)) {
      unawaited(flushPendingWrites());
      if (localBlock != null) return NoteModel.fromBlock(localBlock);
    }

    final response = await _api.getBlock(bid: bid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final block = BlockModel(data: blockData);
    if (_blockIsNewerThan(localBlock, _blockChangedAt(block))) {
      return NoteModel.fromBlock(localBlock!);
    }
    await _store.saveBlock(bid, block);
    return NoteModel.fromBlock(block);
  }

  // ── 写操作 ─────────────────────────────────────────────────

  Future<NoteModel> createNote({
    required String title,
    required String content,
    required String collectionBid,
  }) async {
    final nodeBid = _nodeBid;
    final bid = generateBidV2(nodeBid);
    final now = _blockTimestampNow();
    final data = <String, dynamic>{
      'bid': bid,
      'model': _noteModelId,
      'name': title,
      'content': content,
      'node_bid': nodeBid,
      'link': [collectionBid],
      'tag': <String>[],
      'add_time': now,
      'update_time': now,
    };

    final block = BlockModel(data: data);
    await _store.saveBlock(bid, block);
    await _store.addBidToCollection(collectionBid, bid);
    await _store.markPendingWrite(bid);

    unawaited(() async {
      try {
        await _api.saveBlock(data: data);
        await _store.clearPendingWrite(bid);
      } catch (e) {
        debugPrint('[NoteService] Background createNote failed: $e');
      }
    }());

    return NoteModel.fromBlock(block);
  }

  Future<void> updateNote({
    required String bid,
    required String title,
    required String content,
    DateTime? updatedAt,
  }) async {
    final updateTime = _blockTimestamp(updatedAt);
    final localBlock = await _store.getBlock(bid);
    if (_blockIsNewerThan(localBlock, updatedAt)) return;

    Map<String, dynamic> updated = localBlock != null
        ? Map<String, dynamic>.from(localBlock.data)
        : <String, dynamic>{'bid': bid, 'model': _noteModelId};

    if (_needsRemoteBase(updated)) {
      try {
        final response = await _api.getBlock(bid: bid);
        final data = response['data'];
        final remoteData = data is Map<String, dynamic> ? data : response;
        updated = {...Map<String, dynamic>.from(remoteData), ...updated};
      } catch (_) {
        // 远端基准获取失败时继续使用本地完整缓存，写入会进入待同步队列。
      }
    }

    updated['bid'] = bid;
    updated['model'] ??= _noteModelId;
    updated['name'] = title;
    updated['content'] = content;
    updated['update_time'] = updateTime;

    if (localBlock != null) {
      final localLink = localBlock.data['link'];
      final updatedLink = updated['link'];
      if (localLink != null && (updatedLink is! List || updatedLink.isEmpty)) {
        updated['link'] = localLink;
      }
    }

    final latestLocalBlock = await _store.getBlock(bid);
    if (_blockIsNewerThan(latestLocalBlock, updatedAt)) return;

    await _store.saveBlock(bid, BlockModel(data: updated));
    await _store.markPendingWrite(bid);
    try {
      await _api.saveBlock(data: updated);
      await _store.clearPendingWrite(bid);
    } catch (e) {
      debugPrint('[NoteService] Background updateNote failed: $e');
    }
  }

  /// 仅更新本地缓存（用于实时编辑保存）
  Future<void> updateNoteLocal({
    required String bid,
    required String title,
    required String content,
    DateTime? updatedAt,
  }) async {
    final existing = await _store.getBlock(bid);
    if (_blockIsNewerThan(existing, updatedAt)) return;

    final Map<String, dynamic> data;
    if (existing != null) {
      data = Map<String, dynamic>.from(existing.data);
      data['name'] = title;
      data['content'] = content;
    } else {
      data = <String, dynamic>{
        'bid': bid,
        'model': _noteModelId,
        'name': title,
        'content': content,
      };
      final nodeBid = _tryNodeBid();
      if (nodeBid != null) data['node_bid'] = nodeBid;
    }
    data['update_time'] = _blockTimestamp(updatedAt);
    final latestExisting = await _store.getBlock(bid);
    if (_blockIsNewerThan(latestExisting, updatedAt)) return;
    await _store.saveBlock(bid, BlockModel(data: data));
    await _store.markPendingWrite(bid);
  }

  /// 更新文档的 tag 字段（不影响其他字段）
  Future<void> updateNoteTags({
    required String bid,
    required List<String> tags,
  }) async {
    final localBlock = await _store.getBlock(bid);
    Map<String, dynamic> updated;
    try {
      final response = await _api.getBlock(bid: bid);
      final data = response['data'];
      final blockData = data is Map<String, dynamic> ? data : response;
      updated = Map<String, dynamic>.from(blockData);
      if (localBlock != null) {
        updated = {
          ...updated,
          'name': localBlock.data['name'] ?? updated['name'],
          'content': localBlock.data['content'] ?? updated['content'],
          'update_time':
              localBlock.data['update_time'] ?? updated['update_time'],
        };
      }
    } catch (_) {
      if (localBlock == null) rethrow;
      updated = Map<String, dynamic>.from(localBlock.data);
    }
    updated['bid'] = bid;
    updated['tag'] = tags;
    updated['update_time'] = _blockTimestampNow();
    final nodeBid = updated['node_bid'];
    if (nodeBid is! String || nodeBid.isEmpty) {
      final resolvedNodeBid = _tryNodeBid();
      if (resolvedNodeBid != null) updated['node_bid'] = resolvedNodeBid;
    }
    await _store.saveBlock(bid, BlockModel(data: updated));
    await _store.markPendingWrite(bid);
    try {
      await _api.saveBlock(data: updated, receiverBid: bid.substring(0, 10));
      await _store.clearPendingWrite(bid);
    } catch (e) {
      debugPrint('[NoteService] Background updateNoteTags failed: $e');
    }
  }

  /// 更新文档置顶状态。置顶时写入 is_pinned: true，取消时删除该字段。
  Future<NoteModel> updateNotePinned({
    required String bid,
    required bool isPinned,
  }) async {
    final localBlock = await _store.getBlock(bid);
    Map<String, dynamic> updated;
    try {
      final response = await _api.getBlock(bid: bid);
      final data = response['data'];
      final blockData = data is Map<String, dynamic> ? data : response;
      updated = Map<String, dynamic>.from(blockData);
      if (localBlock != null) {
        updated = {...updated, ...localBlock.data};
      }
    } catch (_) {
      if (localBlock == null) rethrow;
      updated = Map<String, dynamic>.from(localBlock.data);
    }

    updated['bid'] = bid;
    updated['model'] ??= _noteModelId;
    final nodeBid = updated['node_bid'];
    if (nodeBid is! String || nodeBid.isEmpty) {
      final resolvedNodeBid = _tryNodeBid();
      if (resolvedNodeBid != null) updated['node_bid'] = resolvedNodeBid;
    }
    if (isPinned) {
      updated['is_pinned'] = true;
    } else {
      updated.remove('is_pinned');
    }
    updated['update_time'] = _blockTimestampNow();

    final block = BlockModel(data: updated);
    await _store.saveBlock(bid, block);
    await _store.markPendingWrite(bid);
    try {
      await _api.saveBlock(data: updated);
      await _store.clearPendingWrite(bid);
    } catch (e) {
      debugPrint('[NoteService] Background updateNotePinned failed: $e');
    }

    return NoteModel.fromBlock(block);
  }

  Future<void> deleteNote(String bid, {String? collectionBid}) async {
    await _api.deleteBlock(bid: bid);
    if (collectionBid != null) {
      await _store.removeBidFromCollection(collectionBid, bid);
      await _store.removeBlock(bid);
      await _store.clearPendingWrite(bid);
    } else {
      await _store.removeBidEverywhere(bid);
    }
  }

  /// 将 item 移动到目标集合：
  ///   - 从 item 的 link 里移除 fromCollectionBid
  ///   - 加入 targetCollectionBid
  ///   - 提交并更新本地缓存
  Future<void> moveItemToCollection({
    required String bid,
    required String fromCollectionBid,
    required String targetCollectionBid,
  }) async {
    // 拉取最新 block 数据
    final response = await _api.getBlock(bid: bid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final updated = Map<String, dynamic>.from(blockData);

    // 操作 link 字段
    final links = updated['link'] is List
        ? List<String>.from((updated['link'] as List).whereType<String>())
        : <String>[];
    if (fromCollectionBid.isNotEmpty) {
      links.remove(fromCollectionBid); // 移除当前集合（只移除一个）
    }
    if (!links.contains(targetCollectionBid)) {
      links.add(targetCollectionBid); // 加入目标集合
    }
    updated['link'] = links;
    updated['update_time'] = _blockTimestampNow();

    // 提交
    await _api.saveBlock(data: updated);

    // 更新本地 block 缓存
    await _store.saveBlock(bid, BlockModel(data: updated));

    if (fromCollectionBid.isNotEmpty) {
      // 从原集合的本地 BID 列表里移除
      await _store.removeBidFromCollection(fromCollectionBid, bid);
    }

    // 加入目标集合的本地 BID 列表
    await _store.addBidToCollection(targetCollectionBid, bid);
  }

  /// 更新集合的 link_tag 字段
  Future<void> updateCollectionLinkTags(
    String collectionBid,
    List<String> linkTags,
  ) async {
    final response = await _api.getBlock(bid: collectionBid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final updated = Map<String, dynamic>.from(blockData);
    updated['link_tag'] = linkTags;
    updated['update_time'] = _blockTimestampNow();
    await _api.saveBlock(data: updated);
    // 更新本地缓存
    await _store.saveBlock(collectionBid, BlockModel(data: updated));
    await _store.clearTagBids(collectionBid);
  }

  bool _needsRemoteBase(Map<String, dynamic> data) {
    final link = data['link'];
    return data['model'] == null ||
        data['tag'] == null ||
        (link is! List || link.isEmpty);
  }

  String? _tryNodeBid() {
    try {
      return _nodeBid;
    } catch (_) {
      return null;
    }
  }
}
