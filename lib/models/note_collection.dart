import 'package:block_flutter/block_flutter.dart';

class NoteCollection {
  NoteCollection({
    required this.bid,
    required Map<String, dynamic> block,
    this.isDefault = false,
  }) : _block = Map.unmodifiable(Map<String, dynamic>.from(block));

  NoteCollection._internal({
    required this.bid,
    required Map<String, dynamic> block,
    required this.isDefault,
  }) : _block = Map.unmodifiable(block);

  final String bid;
  final Map<String, dynamic> _block;
  final bool isDefault;

  String get title => (_block['name'] as String?)?.trim().isNotEmpty == true
      ? (_block['name'] as String).trim()
      : bid.length > 12 ? '${bid.substring(0, 6)}…${bid.substring(bid.length - 4)}' : bid;

  /// link_tag 字段，通常是字符串列表。
  List<String> get linkTags {
    final raw = _block['link_tag'];
    if (raw is List) return raw.whereType<String>().where((t) => t.trim().isNotEmpty).toList();
    return [];
  }

  Map<String, dynamic> get block => Map<String, dynamic>.from(_block);

  NoteCollection copyWith({String? bid, Map<String, dynamic>? block, bool? isDefault}) {
    return NoteCollection._internal(
      bid: bid ?? this.bid,
      block: block != null ? Map<String, dynamic>.from(block) : Map<String, dynamic>.from(_block),
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {'bid': bid, 'block': _block, 'isDefault': isDefault};

  factory NoteCollection.fromJson(Map<String, dynamic> json) {
    final rawBlock = json['block'];
    final blockMap = rawBlock is Map<String, dynamic> ? Map<String, dynamic>.from(rawBlock) : <String, dynamic>{};
    return NoteCollection._internal(
      bid: (json['bid'] as String?) ?? '',
      block: blockMap,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  factory NoteCollection.fromBlock(BlockModel block) {
    return NoteCollection._internal(bid: block.bid ?? '', block: block.data, isDefault: false);
  }
}
