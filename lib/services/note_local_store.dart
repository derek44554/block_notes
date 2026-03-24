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

  // ── 全量 BID 列表 (无筛选) ──────────────────────────────────

  Future<List<String>> getBids(String collectionBid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_bidsPrefix$collectionBid') ?? [];
  }

  Future<void> saveBids(String collectionBid, List<String> bids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_bidsPrefix$collectionBid', bids);
  }

  // ── 按 Tag 筛选的 BID 列表 ──────────────────────────────────

  String _tagBidsKey(String collectionBid, String tag) =>
      '$_tagBidsPrefix${collectionBid}__$tag';

  Future<List<String>> getBidsForTag(String collectionBid, String tag) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _tagBidsKey(collectionBid, tag);
    final result = prefs.getStringList(key) ?? [];
    print('[CACHE] getBidsForTag: key=$key, found=${result.length} bids');
    return result;
  }

  Future<void> saveBidsForTag(
    String collectionBid,
    String tag,
    List<String> bids,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _tagBidsKey(collectionBid, tag);
    print('[CACHE] saveBidsForTag: key=$key, saving=${bids.length} bids');
    await prefs.setStringList(key, bids);
  }

  // ── Block 详情 ─────────────────────────────────────────────

  Future<BlockModel?> getBlock(String bid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_blockPrefix$bid');
    if (raw == null) return null;
    try {
      return BlockModel(data: jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBlock(String bid, BlockModel block) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_blockPrefix$bid', jsonEncode(block.data));
  }

  Future<void> saveBlocks(List<BlockModel> blocks) async {
    final prefs = await SharedPreferences.getInstance();
    for (final block in blocks) {
      final bid = block.maybeString('bid');
      if (bid != null && bid.isNotEmpty) {
        await prefs.setString('$_blockPrefix$bid', jsonEncode(block.data));
      }
    }
  }

  /// 按 BID 列表批量读取本地已有的 block，返回 {bid: block}
  Future<Map<String, BlockModel>> getBlocks(List<String> bids) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, BlockModel>{};
    for (final bid in bids) {
      final raw = prefs.getString('$_blockPrefix$bid');
      if (raw != null) {
        try {
          result[bid] = BlockModel(data: jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    return result;
  }

  /// 找出本地没有详情的 BID
  Future<List<String>> getMissingBids(List<String> bids) async {
    final prefs = await SharedPreferences.getInstance();
    return bids.where((bid) => prefs.getString('$_blockPrefix$bid') == null).toList();
  }
}
