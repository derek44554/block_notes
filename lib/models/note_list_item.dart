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
  }) {
    return NoteListItemNote(note.copyWith(
      title: title,
      content: summary,
      updatedAt: DateTime.now(),
    ));
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
