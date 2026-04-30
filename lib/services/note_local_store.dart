import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_flutter/block_flutter.dart';

/// 本地持久化：
///   - 集合 BID → 该集合的外链 BID 列表
///   - 集合 BID + Tag → 按 tag 筛选后的外链 BID 列表
///   - BID → BlockModel 详情
class NoteLocalStore {
  NoteLocalStore._();
  static final NoteLocalStore instance = NoteLocalStore._();

  static const _bidsPrefix = 'note_bids_';         // + collectionBid
  static const _tagBidsPrefix = 'note_tag_bids_'; // + collectionBid + tag
  static const _blockPrefix = 'note_block_';       // + bid
  static const _pendingWritesKey = 'note_pending_writes';
  static const _optimisticBidsPrefix = 'note_optimistic_bids_';
  static const _optimisticBidMaxAge = Duration(minutes: 30);

  Future<SharedPreferences>? _prefsFuture;
  final Map<String, List<String>> _bidsCache = {};
  final Map<String, List<String>> _tagBidsCache = {};
  final Map<String, BlockModel> _blockCache = {};
  final Map<String, Map<String, int>> _optimisticBidsCache = {};
  List<String>? _pendingWriteCache;

  Future<SharedPreferences> get _prefs =>
      _prefsFuture ??= SharedPreferences.getInstance();

  // ── 全量 BID 列表 (无筛选) ──────────────────────────────────

  Future<List<String>> getBids(String collectionBid) async {
    final cached = _bidsCache[collectionBid];
    if (cached != null) return List<String>.from(cached);
    final prefs = await _prefs;
    final bids = prefs.getStringList('$_bidsPrefix$collectionBid') ?? [];
    _bidsCache[collectionBid] = _dedupe(bids);
    return List<String>.from(_bidsCache[collectionBid]!);
  }

  Future<void> saveBids(String collectionBid, List<String> bids) async {
    final normalized = _dedupe(bids);
    _bidsCache[collectionBid] = normalized;
    final prefs = await _prefs;
    await prefs.setStringList('$_bidsPrefix$collectionBid', normalized);
  }

  // ── 按 Tag 筛选的 BID 列表 ──────────────────────────────────

  String _tagBidsKey(String collectionBid, String tag) =>
      '$_tagBidsPrefix${collectionBid}__$tag';

  Future<List<String>> getBidsForTag(String collectionBid, String tag) async {
    final key = _tagBidsKey(collectionBid, tag);
    final cached = _tagBidsCache[key];
    if (cached != null) return List<String>.from(cached);
    final prefs = await _prefs;
    final bids = prefs.getStringList(key) ?? [];
    _tagBidsCache[key] = _dedupe(bids);
    return List<String>.from(_tagBidsCache[key]!);
  }

  Future<void> saveBidsForTag(
    String collectionBid,
    String tag,
    List<String> bids,
  ) async {
    final key = _tagBidsKey(collectionBid, tag);
    final normalized = _dedupe(bids);
    _tagBidsCache[key] = normalized;
    final prefs = await _prefs;
    await prefs.setStringList(key, normalized);
  }

  Future<void> clearTagBids(String collectionBid, {String? tag}) async {
    final prefs = await _prefs;
    if (tag != null) {
      final key = _tagBidsKey(collectionBid, tag);
      _tagBidsCache.remove(key);
      await prefs.remove(key);
      return;
    }

    final prefix = '$_tagBidsPrefix${collectionBid}__';
    _tagBidsCache.removeWhere((key, _) => key.startsWith(prefix));
    final removals = <Future<bool>>[];
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      _tagBidsCache.remove(key);
      removals.add(prefs.remove(key));
    }
    await Future.wait(removals);
  }

  // ── Block 详情 ─────────────────────────────────────────────

  Future<BlockModel?> getBlock(String bid) async {
    final cached = _blockCache[bid];
    if (cached != null) return cached;
    final prefs = await _prefs;
    final raw = prefs.getString('$_blockPrefix$bid');
    if (raw == null) return null;
    try {
      final block = BlockModel(data: jsonDecode(raw) as Map<String, dynamic>);
      _blockCache[bid] = block;
      return block;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBlock(String bid, BlockModel block) async {
    _blockCache[bid] = block;
    final prefs = await _prefs;
    await prefs.setString('$_blockPrefix$bid', jsonEncode(block.data));
  }

  Future<void> saveBlocks(List<BlockModel> blocks) async {
    final prefs = await _prefs;
    final writes = <Future<bool>>[];
    for (final block in blocks) {
      final bid = block.maybeString('bid');
      if (bid != null && bid.isNotEmpty) {
        _blockCache[bid] = block;
        writes.add(prefs.setString('$_blockPrefix$bid', jsonEncode(block.data)));
      }
    }
    await Future.wait(writes);
  }

  Future<void> removeBlock(String bid) async {
    _blockCache.remove(bid);
    final prefs = await _prefs;
    await prefs.remove('$_blockPrefix$bid');
  }

  /// 按 BID 列表批量读取本地已有的 block，返回 {bid: block}
  Future<Map<String, BlockModel>> getBlocks(List<String> bids) async {
    final prefs = await _prefs;
    final result = <String, BlockModel>{};
    for (final bid in bids) {
      final cached = _blockCache[bid];
      if (cached != null) {
        result[bid] = cached;
        continue;
      }
      final raw = prefs.getString('$_blockPrefix$bid');
      if (raw != null) {
        try {
          final block = BlockModel(data: jsonDecode(raw) as Map<String, dynamic>);
          _blockCache[bid] = block;
          result[bid] = block;
        } catch (_) {}
      }
    }
    return result;
  }

  /// 找出本地没有详情的 BID
  Future<List<String>> getMissingBids(List<String> bids) async {
    final prefs = await _prefs;
    return _dedupe(bids)
        .where((bid) =>
            !_blockCache.containsKey(bid) &&
            !prefs.containsKey('$_blockPrefix$bid'))
        .toList();
  }

  // ── 本地列表修正 ───────────────────────────────────────────

  Future<void> addBidToCollection(String collectionBid, String bid) async {
    final bids = await getBids(collectionBid);
    if (!bids.contains(bid)) {
      await saveBids(collectionBid, [bid, ...bids]);
    }
    await markOptimisticBid(collectionBid, bid);
    await clearTagBids(collectionBid);
  }

  Future<void> removeBidFromCollection(String collectionBid, String bid) async {
    final bids = await getBids(collectionBid);
    if (bids.contains(bid)) {
      await saveBids(
        collectionBid,
        bids.where((existing) => existing != bid).toList(),
      );
    }
    await _removeBidFromTagCaches(collectionBid, bid);
    await clearOptimisticBid(collectionBid, bid);
  }

  Future<void> removeBidEverywhere(String bid) async {
    final prefs = await _prefs;
    final writes = <Future<bool>>[];

    for (final key in prefs.getKeys()) {
      if (key.startsWith(_bidsPrefix)) {
        final collectionBid = key.substring(_bidsPrefix.length);
        final bids = prefs.getStringList(key) ?? const <String>[];
        if (bids.contains(bid)) {
          final updated = bids.where((existing) => existing != bid).toList();
          _bidsCache[collectionBid] = updated;
          writes.add(prefs.setStringList(key, updated));
        }
      } else if (key.startsWith(_tagBidsPrefix)) {
        final bids = prefs.getStringList(key) ?? const <String>[];
        if (bids.contains(bid)) {
          final updated = bids.where((existing) => existing != bid).toList();
          _tagBidsCache[key] = updated;
          writes.add(prefs.setStringList(key, updated));
        }
      } else if (key.startsWith(_optimisticBidsPrefix)) {
        final collectionBid = key.substring(_optimisticBidsPrefix.length);
        final optimistic = await _loadOptimisticBids(collectionBid);
        if (optimistic.remove(bid) != null) {
          writes.add(_saveOptimisticBids(collectionBid, optimistic));
        }
      }
    }

    await Future.wait(writes);
    await removeBlock(bid);
    await clearPendingWrite(bid);
  }

  Future<void> _removeBidFromTagCaches(String collectionBid, String bid) async {
    final prefs = await _prefs;
    final prefix = '$_tagBidsPrefix${collectionBid}__';
    final writes = <Future<bool>>[];
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      final bids = prefs.getStringList(key) ?? const <String>[];
      if (!bids.contains(bid)) continue;
      final updated = bids.where((existing) => existing != bid).toList();
      _tagBidsCache[key] = updated;
      writes.add(prefs.setStringList(key, updated));
    }
    await Future.wait(writes);
  }

  // ── 待同步写入 ─────────────────────────────────────────────

  Future<List<String>> getPendingWriteBids() async {
    if (_pendingWriteCache != null) {
      return List<String>.from(_pendingWriteCache!);
    }
    final prefs = await _prefs;
    _pendingWriteCache = _dedupe(prefs.getStringList(_pendingWritesKey) ?? []);
    return List<String>.from(_pendingWriteCache!);
  }

  Future<void> markPendingWrite(String bid) async {
    final bids = await getPendingWriteBids();
    if (bids.contains(bid)) return;
    final updated = [bid, ...bids];
    _pendingWriteCache = updated;
    final prefs = await _prefs;
    await prefs.setStringList(_pendingWritesKey, updated);
  }

  Future<void> clearPendingWrite(String bid) async {
    final bids = await getPendingWriteBids();
    if (!bids.contains(bid)) return;
    final updated = bids.where((existing) => existing != bid).toList();
    _pendingWriteCache = updated;
    final prefs = await _prefs;
    if (updated.isEmpty) {
      await prefs.remove(_pendingWritesKey);
    } else {
      await prefs.setStringList(_pendingWritesKey, updated);
    }
  }

  // ── 乐观 BID：只短期保留本地新增项，避免永久脏缓存 ─────────────

  Future<void> markOptimisticBid(String collectionBid, String bid) async {
    final optimistic = await _loadOptimisticBids(collectionBid);
    optimistic[bid] = DateTime.now().millisecondsSinceEpoch;
    await _saveOptimisticBids(collectionBid, optimistic);
  }

  Future<void> clearOptimisticBid(String collectionBid, String bid) async {
    final optimistic = await _loadOptimisticBids(collectionBid);
    if (optimistic.remove(bid) == null) return;
    await _saveOptimisticBids(collectionBid, optimistic);
  }

  Future<void> clearOptimisticBids(
    String collectionBid,
    Iterable<String> bids,
  ) async {
    final optimistic = await _loadOptimisticBids(collectionBid);
    var changed = false;
    for (final bid in bids) {
      changed = optimistic.remove(bid) != null || changed;
    }
    if (changed) await _saveOptimisticBids(collectionBid, optimistic);
  }

  Future<Set<String>> getOptimisticBids(String collectionBid) async {
    final optimistic = await _loadOptimisticBids(collectionBid);
    final now = DateTime.now().millisecondsSinceEpoch;
    var pruned = false;
    optimistic.removeWhere((_, timestamp) {
      final expired =
          now - timestamp > _optimisticBidMaxAge.inMilliseconds;
      pruned = pruned || expired;
      return expired;
    });
    if (pruned) await _saveOptimisticBids(collectionBid, optimistic);
    return optimistic.keys.toSet();
  }

  Future<Map<String, int>> _loadOptimisticBids(String collectionBid) async {
    final cached = _optimisticBidsCache[collectionBid];
    if (cached != null) return Map<String, int>.from(cached);

    final prefs = await _prefs;
    final raw = prefs.getString('$_optimisticBidsPrefix$collectionBid');
    final result = <String, int>{};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key;
            final value = entry.value;
            if (key is String && value is num) {
              result[key] = value.toInt();
            }
          }
        }
      } catch (_) {}
    }
    _optimisticBidsCache[collectionBid] = result;
    return Map<String, int>.from(result);
  }

  Future<bool> _saveOptimisticBids(
    String collectionBid,
    Map<String, int> bids,
  ) async {
    _optimisticBidsCache[collectionBid] = Map<String, int>.from(bids);
    final prefs = await _prefs;
    final key = '$_optimisticBidsPrefix$collectionBid';
    if (bids.isEmpty) {
      return prefs.remove(key);
    }
    return prefs.setString(key, jsonEncode(bids));
  }

  List<String> _dedupe(Iterable<String> bids) {
    final seen = <String>{};
    final result = <String>[];
    for (final bid in bids) {
      if (bid.isEmpty || !seen.add(bid)) continue;
      result.add(bid);
    }
    return result;
  }
}
