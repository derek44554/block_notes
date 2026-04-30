import 'package:block_flutter/block_flutter.dart';
import 'note_model.dart';
import 'note_collection.dart';

const _noteModelId = '93b133932057a254cc15d0f09c91ca98';
const _collectionModelId = '1635e536a5a331a283f9da56b7b51774';

/// 集合列表里的一项，可能是子集合也可能是备忘录文档
sealed class NoteListItem {
  const NoteListItem();

  String get bid;
  String get title;

  factory NoteListItem.fromBlock(BlockModel block) {
    final model = block.maybeString('model') ?? '';
    // 明确是集合 model → 集合；是 note model 或有 content → 文档
    if (model == _collectionModelId) {
      return NoteListItemCollection(NoteCollection.fromBlock(block));
    }
    final hasContent = block.has('content') || block.has('body');
    if (model == _noteModelId || hasContent) {
      return NoteListItemNote(NoteModel.fromBlock(block));
    }
    // 兜底：当集合处理
    return NoteListItemCollection(NoteCollection.fromBlock(block));
  }
}

class NoteListItemNote extends NoteListItem {
  const NoteListItemNote(this.note);
  final NoteModel note;

  @override
  String get bid => note.bid;
  @override
  String get title => note.title;

  NoteListItemNote copyWith({
    String? title,
    String? summary,
    DateTime? updatedAt,
    bool? isPinned,
  }) {
    return NoteListItemNote(
      note.copyWith(
        title: title,
        content: summary,
        updatedAt: updatedAt,
        isPinned: isPinned,
      ),
    );
  }
}

class NoteListItemCollection extends NoteListItem {
  const NoteListItemCollection(this.collection);
  final NoteCollection collection;

  @override
  String get bid => collection.bid;
  @override
  String get title => collection.title;
}

List<NoteListItem> sortNoteListItems(
  Iterable<NoteListItem> items, {
  Map<String, int> originalIndexes = const {},
}) {
  final list = items.toList(growable: false);
  final indexed = [
    for (var i = 0; i < list.length; i++) (index: i, item: list[i]),
  ];
  final collections = <({int index, NoteListItem item})>[];
  final pinnedNotes = <({int index, NoteListItemNote item})>[];
  final notes = <({int index, NoteListItemNote item})>[];

  for (final entry in indexed) {
    final item = entry.item;
    if (item is NoteListItemCollection) {
      collections.add(entry);
    } else if (item is NoteListItemNote && item.note.isPinned) {
      pinnedNotes.add((index: entry.index, item: item));
    } else if (item is NoteListItemNote) {
      notes.add((index: entry.index, item: item));
    }
  }

  int fallbackIndex(String bid, int index) => originalIndexes[bid] ?? index;

  int compareNotes(
    ({int index, NoteListItemNote item}) a,
    ({int index, NoteListItemNote item}) b,
  ) {
    final timeCompare = b.item.note.sortUpdatedAt.compareTo(
      a.item.note.sortUpdatedAt,
    );
    if (timeCompare != 0) return timeCompare;
    return fallbackIndex(a.item.bid, a.index).compareTo(
      fallbackIndex(b.item.bid, b.index),
    );
  }

  pinnedNotes.sort(compareNotes);
  notes.sort(compareNotes);
  return [
    ...collections.map((entry) => entry.item),
    ...pinnedNotes.map((entry) => entry.item),
    ...notes.map((entry) => entry.item),
  ];
}
