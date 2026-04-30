import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_flutter/block_flutter.dart';

class ConnectionProvider extends ChangeNotifier {
  static const _storageKey = 'block_connections';
  static const _activeKey = 'block_active_index';

  List<ConnectionModel> _connections = [];
  ConnectionModel? _activeConnection;
  Future<SharedPreferences>? _prefsFuture;

  List<ConnectionModel> get connections => List.unmodifiable(_connections);
  ConnectionModel? get activeConnection => _activeConnection;
  bool get hasActiveConnection => _activeConnection != null;

  Future<SharedPreferences> get _prefs =>
      _prefsFuture ??= SharedPreferences.getInstance();

  Future<void> load() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_storageKey) ?? [];
    _connections = [];
    for (final item in raw) {
      try {
        _connections.add(
          ConnectionModel.fromJson(jsonDecode(item) as Map<String, dynamic>),
        );
      } catch (_) {}
    }
    final activeIndex = prefs.getInt(_activeKey) ?? 0;
    if (_connections.isNotEmpty) {
      _activeConnection = _connections[activeIndex.clamp(0, _connections.length - 1)];
    } else {
      _activeConnection = null;
    }
    notifyListeners();
    for (final c in List.unmodifiable(_connections)) {
      unawaited(_refreshNodeData(c));
    }
  }

  Future<void> _refreshNodeData(ConnectionModel connection) async {
    try {
      final nodeData = await ApiClient(connection: connection).postToBridge(
        protocol: 'open',
        routing: '/node/node',
        data: const {},
      );
      final index = _connections.indexWhere((c) => c.address == connection.address);
      if (index == -1) return;
      _connections[index] = _connections[index].copyWith(nodeData: nodeData);
      if (_activeConnection?.address == connection.address) {
        _activeConnection = _connections[index];
      }
      await _persist();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> addConnection(ConnectionModel connection) async {
    _connections.add(connection);
    if (_connections.length == 1) {
      _activeConnection = connection;
      final prefs = await _prefs;
      await prefs.setInt(_activeKey, 0);
    }
    await _persist();
    notifyListeners();
    if (connection.nodeData == null) unawaited(_refreshNodeData(connection));
  }

  Future<void> removeConnection(int index) async {
    if (index < 0 || index >= _connections.length) return;
    final prefs = await _prefs;
    final activeIndex = prefs.getInt(_activeKey) ?? 0;
    _connections.removeAt(index);

    if (_connections.isEmpty) {
      _activeConnection = null;
      await prefs.remove(_activeKey);
    } else {
      final nextActiveIndex = index == activeIndex
          ? index.clamp(0, _connections.length - 1)
          : index < activeIndex
              ? (activeIndex - 1).clamp(0, _connections.length - 1)
              : activeIndex.clamp(0, _connections.length - 1);
      _activeConnection = _connections[nextActiveIndex];
      await prefs.setInt(_activeKey, nextActiveIndex);
    }

    await _persist();
    notifyListeners();
  }

  Future<void> setActive(int index) async {
    if (index < 0 || index >= _connections.length) return;
    _activeConnection = _connections[index];
    final prefs = await _prefs;
    await prefs.setInt(_activeKey, index);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await _prefs;
    await prefs.setStringList(
      _storageKey,
      _connections.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}
