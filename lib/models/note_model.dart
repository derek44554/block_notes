import 'package:block_flutter/block_flutter.dart';

/// 备忘录数据模型，对应 Block 网络上的一个 block
class NoteModel {
  NoteModel({
    required this.bid,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    DateTime? sortUpdatedAt,
    this.tags = const [],
    this.isPinned = false,
  }) : sortUpdatedAt = sortUpdatedAt ?? updatedAt;

  factory NoteModel.fromBlock(BlockModel block) {
    final bid = block.maybeString('bid') ?? '';
    final title =
        block.maybeString('name') ?? block.maybeString('title') ?? '无标题';
    final content =
        block.maybeString('content') ?? block.maybeString('body') ?? '';
    final addTime = block.getDateTime('add_time');
    final createdTime = block.getDateTime('created_at');
    final updateTime = block.getDateTime('update_time');
    final updatedTime = block.getDateTime('updated_at');
    final createdAt = addTime ?? createdTime ?? DateTime.now();
    final updatedAt = updateTime ?? updatedTime ?? addTime ?? createdAt;
    final sortUpdatedAt =
        updateTime ??
        updatedTime ??
        addTime ??
        createdTime ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final rawTags = block.data['tag'];
    final tags = rawTags is List
        ? rawTags.whereType<String>().where((t) => t.trim().isNotEmpty).toList()
        : <String>[];
    return NoteModel(
      bid: bid,
      title: title,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sortUpdatedAt: sortUpdatedAt,
      tags: tags,
      isPinned: block.data['is_pinned'] == true,
    );
  }

  final String bid;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime sortUpdatedAt;
  final List<String> tags;
  final bool isPinned;

  NoteModel copyWith({
    String? title,
    String? content,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? sortUpdatedAt,
    bool? isPinned,
  }) {
    final nextUpdatedAt = updatedAt ?? this.updatedAt;
    return NoteModel(
      bid: bid,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: nextUpdatedAt,
      sortUpdatedAt:
          sortUpdatedAt ??
          (updatedAt != null ? nextUpdatedAt : this.sortUpdatedAt),
      tags: tags ?? this.tags,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  String get preview {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed;
  }

  String get formattedDate {
    return '${updatedAt.year}/${updatedAt.month.toString().padLeft(2, '0')}/${updatedAt.day.toString().padLeft(2, '0')}';
  }
}
