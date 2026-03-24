import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note_collection.dart';

const _collectionsKey = 'note_collections';
const _lastOpenedKey = 'note_last_opened_bid';

class CollectionProvider extends ChangeNotifier {
  List<NoteCollection> _collections = [];
  String? _lastOpenedBid;

  List<NoteCollection> get collections => List.unmodifiable(_collections);
  String? get lastOpenedBid => _lastOpenedBid;

  /// 非默认集合列表
  List<NoteCollection> get regularCollections =>
      _collections.where((c) => !c.isDefault).toList();

  /// 当前默认集合（最多一个）
  NoteCollection? get defaultCollection {
    try {
      return _collections.firstWhere((c) => c.isDefault);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_collectionsKey) ?? [];
    try {
      _collections = raw
          .map((e) => NoteCollection.fromJson(jsonDecode(e) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _collections = [];
    }
    _lastOpenedBid = prefs.getString(_lastOpenedKey);
    notifyListeners();
  }

  Future<void> addCollection(NoteCollection collection) async {
    final idx = _collections.indexWhere((c) => c.bid == collection.bid);
    if (idx >= 0) {
      final updated = [..._collections];
      updated[idx] = collection;
      _collections = updated;
    } else {
      _collections = [..._collections, collection];
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeCollection(String bid) async {
    _collections = _collections.where((c) => c.bid != bid).toList();
    await _persist();
    notifyListeners();
  }

  /// 记录最后打开的集合 BID（null = 首页）
  Future<void> setLastOpened(String? bid) async {
    _lastOpenedBid = bid;
    final prefs = await SharedPreferences.getInstance();
    if (bid != null) {
      await prefs.setString(_lastOpenedKey, bid);
    } else {
      await prefs.remove(_lastOpenedKey);
    }
  }

  /// 设置某个集合为默认（同时清除其他集合的默认标记）
  Future<void> setDefault(String bid) async {
    _collections = _collections.map((c) => c.copyWith(isDefault: c.bid == bid)).toList();
    await _persist();
    notifyListeners();
  }

  /// 取消默认
  Future<void> clearDefault() async {
    _collections = _collections.map((c) => c.copyWith(isDefault: false)).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _collectionsKey,
      _collections.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}
