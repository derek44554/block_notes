import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/note_collection.dart';
import 'providers/connection_provider.dart';
import 'providers/collection_provider.dart';
import 'providers/note_provider.dart';
import 'screens/folders_screen.dart';
import 'screens/notes_list_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  final connectionProvider = ConnectionProvider();
  final collectionProvider = CollectionProvider();

  await Future.wait([
    connectionProvider.load(),
    collectionProvider.load(),
  ]);

  // 启动前就确定初始路由，避免首页闪烁
  final lastBid = collectionProvider.lastOpenedBid;
  final NoteCollection? lastCollection = lastBid != null
      ? collectionProvider.collections.where((c) => c.bid == lastBid).firstOrNull
      : null;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connectionProvider),
        ChangeNotifierProvider.value(value: collectionProvider),
        ChangeNotifierProxyProvider<ConnectionProvider, NoteProvider>(
          create: (ctx) => NoteProvider(ctx.read<ConnectionProvider>()),
          update: (ctx, conn, prev) => prev ?? NoteProvider(conn),
        ),
      ],
      child: BlockNotesApp(initialCollection: lastCollection),
    ),
  );
}

class BlockNotesApp extends StatelessWidget {
  const BlockNotesApp({super.key, this.initialCollection});

  final NoteCollection? initialCollection;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '备忘录',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      onGenerateRoute: (settings) {
        // 必须提供，onGenerateInitialRoutes 才能工作
        if (settings.name == '/') {
          return MaterialPageRoute(builder: (_) => const FoldersScreen());
        }
        if (settings.name == '/collection' && initialCollection != null) {
          return MaterialPageRoute(
            builder: (_) => NotesListScreen(collection: initialCollection!),
          );
        }
        return MaterialPageRoute(builder: (_) => const FoldersScreen());
      },
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute(builder: (_) => const FoldersScreen()),
        if (initialCollection != null)
          MaterialPageRoute(
            builder: (_) => NotesListScreen(collection: initialCollection!),
          ),
      ],
    );
  }
}
