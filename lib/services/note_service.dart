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
const _batchSize = 20;

class NoteService {
  NoteService(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  ConnectionModel get _connection {
    final c = _connectionProvider.activeConnection;
    if (c == null) throw StateError('No active connection available.');
    return c;
  }

  BlockApi get _api => BlockApi(connection: _connection);

  String get _nodeBid {
    final nodeData = _connection.nodeData;
    // ignore: avoid_print
    print('[NoteService] nodeData keys=${nodeData?.keys.toList()}, nodeData=$nodeData');
    if (nodeData == null) throw StateError('Node data not available.');
    // /node/node 响应结构: { data: { bid: '...' } } 或直接 { bid: '...' }
    final inner = nodeData['data'];
    final searchMap = inner is Map<String, dynamic> ? inner : nodeData;
    final bid = searchMap['bid'] as String? ??
        searchMap['sender'] as String? ??
        searchMap['node_bid'] as String?;
    if (bid == null || bid.isEmpty) throw StateError('Node BID not found in nodeData: $nodeData');
    return bid;
  }

  final _store = NoteLocalStore.instance;

  // ── 集合验证 ───────────────────────────────────────────────

  Future<NoteCollection> fetchCollection(String bid) async {
    final response = await _api.getBlock(bid: bid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    return NoteCollection.fromBlock(BlockModel(data: blockData));
  }

  /// 在节点上新建一个集合 block，返回创建好的 NoteCollection
  /// [parentBid] 不为空时，新集合的 link 里放父集合 BID
  Future<NoteCollection> createCollection(String name, {String? parentBid}) async {
    final nodeBid = _nodeBid;
    final bid = generateBidV2(nodeBid);
    final data = <String, dynamic>{
      'bid': bid,
      'name': name,
      'model': _collectionModelId,
      'node_bid': nodeBid,
      'permission_level': 0,
      'tag': <String>[],
      'link': parentBid != null ? [parentBid] : <String>[],
    };
    // ignore: avoid_print
    print('[NoteService] createCollection: bid=$bid, nodeBid=$nodeBid');
    try {
      final result = await _api.saveBlock(data: data, receiverBid: nodeBid);
      // ignore: avoid_print
      print('[NoteService] createCollection result: $result');
    } catch (e, st) {
      // ignore: avoid_print
      print('[NoteService] createCollection ERROR: $e\n$st');
      rethrow;
    }
    final block = BlockModel(data: data);
    await _store.saveBlock(bid, block);
    if (parentBid != null) {
      final bids = await _store.getBids(parentBid);
      if (!bids.contains(bid)) {
        await _store.saveBids(parentBid, [bid, ...bids]);
      }
    }
    return NoteCollection.fromBlock(block);
  }

  /// 加入集合：把 [currentCollectionBid] 加入到 [targetBid] block 的 link 字段里
  Future<void> joinCollection({
    required String targetBid,
    required String currentCollectionBid,
  }) async {
    // ignore: avoid_print
    print('[NoteService] joinCollection: targetBid=$targetBid, currentBid=$currentCollectionBid');
    // 获取目标 block 最新数据
    final response = await _api.getBlock(bid: targetBid);
    // ignore: avoid_print
    print('[NoteService] joinCollection getBlock response: $response');
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
    // ignore: avoid_print
    print('[NoteService] joinCollection saveBlock data: $updatedData');
    try {
      final result = await _api.saveBlock(data: updatedData);
      // ignore: avoid_print
      print('[NoteService] joinCollection result: $result');
    } catch (e, st) {
      // ignore: avoid_print
      print('[NoteService] joinCollection ERROR: $e\n$st');
      rethrow;
    }
  }

  // ── 核心同步 ───────────────────────────────────────────────

  /// 拉取集合自身最新 block 并更新本地缓存，返回最新 BlockModel
  Future<BlockModel> refreshCollection(String collectionBid) async {
    final response = await _api.getBlock(bid: collectionBid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    // ignore: avoid_print
    print('[NoteService] refreshCollection $collectionBid => link_tag=${blockData['link_tag']}');
    final block = BlockModel(data: blockData);
    await _store.saveBlock(collectionBid, block);
    return block;
  }

  /// 同步外链 BID 列表并持久化（合并本地新增项，防止索引延迟导致本地项消失）
  Future<List<String>> syncCollection(String collectionBid) async {
    final freshBids = await _syncBids(collectionBid);
    final localBids = await _store.getBids(collectionBid);
    
    // 合并策略：保留本地存在但服务器尚未索引到的 BID，且保持它们在顶部
    final mergedBids = List<String>.from(freshBids);
    final freshSet = Set<String>.from(freshBids);
    
    // 将本地有但服务器没有的项（通常是刚创建还没索引到的）插入到最前面
    for (final bid in localBids.reversed) {
      if (!freshSet.contains(bid)) {
        mergedBids.insert(0, bid);
      }
    }
    
    await _store.saveBids(collectionBid, mergedBids);
    return mergedBids;
  }

  /// 按 link_tag 筛选同步外链 BID（同样应用合并策略）
  Future<List<String>> syncCollectionByTag(String collectionBid, String tag) async {
    final freshBids = await _syncBids(collectionBid, tag: tag);
    final localBids = await _store.getBidsForTag(collectionBid, tag);
    
    final mergedBids = List<String>.from(freshBids);
    final freshSet = Set<String>.from(freshBids);
    
    for (final bid in localBids.reversed) {
      if (!freshSet.contains(bid)) {
        mergedBids.insert(0, bid);
      }
    }
    
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
    for (var i = 0; i < missing.length; i += _batchSize) {
      final batch = missing.sublist(i, (i + _batchSize).clamp(0, missing.length));
      try {
        final response = await _api.getMultipleBlocks(bids: batch);
        final data = response['data'] ?? response;
        final blocks = data['blocks'];
        if (blocks is List) {
          final models = blocks
              .whereType<Map<String, dynamic>>()
              .map((e) => BlockModel(data: e))
              .toList();
          await _store.saveBlocks(models);
        }
      } catch (_) {}
    }

    return freshBids;
  }

  /// 从本地缓存按 link_tag 筛选 BID 列表
  Future<List<String>> getLocalBidsByTag(String collectionBid, String tag) =>
      _store.getBidsForTag(collectionBid, tag);

  /// 从本地读取集合的 BID 列表
  Future<List<String>> getLocalBids(String collectionBid) =>
      _store.getBids(collectionBid);

  /// 从本地读取 BID 列表对应的列表项（文档或子集合），集合置顶
  Future<List<NoteListItem>> getLocalItems(List<String> bids) async {
    final blocks = await _store.getBlocks(bids);
    final items = bids
        .where((bid) => blocks.containsKey(bid))
        .map((bid) => NoteListItem.fromBlock(blocks[bid]!))
        .toList();
    // 集合排前，文档排后，各自保持原有顺序
    items.sort((a, b) {
      final aIsCol = a is NoteListItemCollection;
      final bIsCol = b is NoteListItemCollection;
      if (aIsCol == bIsCol) return 0;
      return aIsCol ? -1 : 1;
    });
    return items;
  }

  // ── 单个 block 刷新（进入文档时调用）─────────────────────

  /// 拉取单个 block 最新数据，更新本地缓存，返回最新 NoteModel
  Future<NoteModel> refreshNote(String bid) async {
    final response = await _api.getBlock(bid: bid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final block = BlockModel(data: blockData);
    await _store.saveBlock(bid, block);
    return NoteModel.fromBlock(block);
  }

  // ── 写操作 ─────────────────────────────────────────────────

  Future<NoteModel> createNote({
    required String title,
    required String content,
    required String collectionBid,
  }) async {
    final bid = generateBidV2(_nodeBid);
    final data = {
      'bid': bid,
      'model': _noteModelId,
      'name': title,
      'content': content,
      'link': [collectionBid],
      'add_time': DateTime.now().toIso8601String(),
    };
    
    // 1. 立即持久化到本地缓存，确保本地能立刻看到
    final block = BlockModel(data: data);
    await _store.saveBlock(bid, block);
    
    // 将新 bid 加入集合的本地 BID 列表
    final bids = await _store.getBids(collectionBid);
    if (!bids.contains(bid)) {
      final newBids = [bid, ...bids];
      await _store.saveBids(collectionBid, newBids);
      // 同时更新按 tag 筛选的缓存（如果有的话），这里简单起见，直接清空 tag 缓存让它下次重新拉取
      // 或者更精细地更新，但清空是最安全的
    }

    // 2. 异步发送到网络，不阻塞返回
    unawaited(() async {
      try {
        await _api.saveBlock(data: data);
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
  }) async {
    // 1. 先同步到本地，保证 UI 响应和本地数据最新
    await updateNoteLocal(bid: bid, title: title, content: content);

    // 2. 准备同步到服务器。
    // 为了不丢失 link、tag 等关键字段，我们合并本地缓存和远端数据
    final localBlock = await _store.getBlock(bid);
    
    Map<String, dynamic> updated;
    try {
      // 尝试拉取远端数据作为基准（以获取最新的 link/tag/node_bid 等）
      final response = await _api.getBlock(bid: bid);
      final data = response['data'];
      final remoteData = data is Map<String, dynamic> ? data : response;
      updated = Map<String, dynamic>.from(remoteData);
    } catch (_) {
      // 远端拉取失败（可能是新文档还没同步上去），则以本地为基准
      updated = localBlock != null 
          ? Map<String, dynamic>.from(localBlock.data) 
          : {'bid': bid, 'model': _noteModelId};
    }

    // 3. 覆盖用户修改的字段
    updated['bid'] = bid;
    updated['name'] = title;
    updated['content'] = content;
    
    // 关键：如果本地有 link 且远端没有（或者远端为空），强制保留本地 link
    if (localBlock != null) {
      final localLink = localBlock.data['link'];
      if (localLink != null && (updated['link'] == null || (updated['link'] as List).isEmpty)) {
        updated['link'] = localLink;
      }
    }

    if (updated['node_bid'] == null || (updated['node_bid'] as String).isEmpty) {
      // updated['node_bid'] = _nodeBid;
    }

    // 4. 提交到服务器
    try {
      await _api.saveBlock(data: updated);
    } catch (e) {
      debugPrint('[NoteService] Background updateNote failed: $e');
    }
    
    // 5. 提交成功后再写一次本地，确保本地缓存是最终完整的版本
    await _store.saveBlock(bid, BlockModel(data: updated));
  }

  /// 仅更新本地缓存（用于实时编辑保存）
  Future<void> updateNoteLocal({
    required String bid,
    required String title,
    required String content,
  }) async {
    final existing = await _store.getBlock(bid);
    final Map<String, dynamic> data;
    if (existing != null) {
      data = Map<String, dynamic>.from(existing.data);
      data['name'] = title;
      data['content'] = content;
    } else {
      data = {
        'bid': bid,
        'model': _noteModelId,
        'name': title,
        'content': content,
        'node_bid': _nodeBid,
      };
    }
    await _store.saveBlock(bid, BlockModel(data: data));
  }

  /// 更新文档的 tag 字段（不影响其他字段）
  Future<void> updateNoteTags({
    required String bid,
    required List<String> tags,
  }) async {
    final response = await _api.getBlock(bid: bid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final updated = Map<String, dynamic>.from(blockData);
    updated['bid'] = bid;
    updated['tag'] = tags;
    if (updated['node_bid'] == null || (updated['node_bid'] as String).isEmpty) {
      updated['node_bid'] = _nodeBid;
    }
    await _api.saveBlock(data: updated, receiverBid: bid.substring(0, 10));
    await _store.saveBlock(bid, BlockModel(data: updated));
  }

  Future<void> deleteNote(String bid) async {
    await _api.deleteBlock(bid: bid);
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
    links.remove(fromCollectionBid);          // 移除当前集合（只移除一个）
    if (!links.contains(targetCollectionBid)) {
      links.add(targetCollectionBid);         // 加入目标集合
    }
    updated['link'] = links;

    // 提交
    await _api.saveBlock(data: updated);

    // 更新本地 block 缓存
    await _store.saveBlock(bid, BlockModel(data: updated));

    // 从原集合的本地 BID 列表里移除
    final fromBids = await _store.getBids(fromCollectionBid);
    if (fromBids.contains(bid)) {
      await _store.saveBids(fromCollectionBid, fromBids.where((b) => b != bid).toList());
    }

    // 加入目标集合的本地 BID 列表
    final toBids = await _store.getBids(targetCollectionBid);
    if (!toBids.contains(bid)) {
      await _store.saveBids(targetCollectionBid, [bid, ...toBids]);
    }
  }

  /// 更新集合的 link_tag 字段
  Future<void> updateCollectionLinkTags(String collectionBid, List<String> linkTags) async {
    final response = await _api.getBlock(bid: collectionBid);
    final data = response['data'];
    final blockData = data is Map<String, dynamic> ? data : response;
    final updated = Map<String, dynamic>.from(blockData);
    updated['link_tag'] = linkTags;
    await _api.saveBlock(data: updated);
    // 更新本地缓存
    await _store.saveBlock(collectionBid, BlockModel(data: updated));
  }
}
