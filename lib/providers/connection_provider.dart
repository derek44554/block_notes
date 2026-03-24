import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_flutter/block_flutter.dart';

class ConnectionProvider extends ChangeNotifier {
  static const _storageKey = 'block_connections';
  static const _activeKey = 'block_active_index';

  List<ConnectionModel> _connections = [];
  ConnectionModel? _activeConnection;

  List<ConnectionModel> get connections => List.unmodifiable(_connections);
  ConnectionModel? get activeConnection => _activeConnection;
  bool get hasActiveConnection => _activeConnection != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    _connections = raw
        .map((e) => ConnectionModel.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    final activeIndex = prefs.getInt(_activeKey) ?? 0;
    if (_connections.isNotEmpty) {
      _activeConnection = _connections[activeIndex.clamp(0, _connections.length - 1)];
    }
    notifyListeners();
    for (final c in List.unmodifiable(_connections)) {
      _refreshNodeData(c);
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_activeKey, 0);
    }
    await _persist();
    notifyListeners();
    if (connection.nodeData == null) _refreshNodeData(connection);
  }

  Future<void> removeConnection(int index) async {
    _connections.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    final activeIndex = prefs.getInt(_activeKey) ?? 0;
    if (activeIndex >= _connections.length) {
      _activeConnection = _connections.isNotEmpty ? _connections[0] : null;
      await prefs.setInt(_activeKey, 0);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setActive(int index) async {
    if (index < 0 || index >= _connections.length) return;
    _activeConnection = _connections[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeKey, index);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _connections.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}
