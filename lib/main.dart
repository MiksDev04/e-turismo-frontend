import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app/app.dart';

class _AppLifecycleSyncObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ConnectivityService.instance.isOnline) {
      SyncService.instance.sync();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: .env file not found: $e");
  }

  // ── sqflite desktop init ───────────────────────────────────────────────────
  // Required on Windows, Linux, and macOS. Mobile (Android/iOS) uses the
  // default sqflite and does not need this.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await ConnectivityService.instance.startWatching();
  SyncService.instance.listenForConnectivity();
  WidgetsBinding.instance.addObserver(_AppLifecycleSyncObserver());

  // ── Periodic Sync Trigger ──────────────────────────────────────────────────
  Timer.periodic(const Duration(minutes: 5), (_) {
    if (ConnectivityService.instance.isOnline) {
      SyncService.instance.sync();
    }
  });

  final session = await SessionService.instance.loadAndCache();

  // ── Offline infrastructure ─────────────────────────────────────────────────
  if (!kIsWeb && session?.role == 'business') {
    await LocalDatabase.instance.database;
    final dbFilePath = await LocalDatabase.instance.getDatabaseFilePath();
    debugPrint('SQLite DB file path: $dbFilePath');
  } else if (!kIsWeb) {
    debugPrint('Offline sync disabled for ${session?.role ?? 'guest'} role.');
  } else {
    debugPrint('Web platform detected: skipping local SQLite initialization.');
  }

  if (ConnectivityService.instance.isOnline && session?.role == 'business') {
    debugPrint('🚀 main: triggering initial sync...');
    SyncService.instance.sync();
  }

  if (!kIsWeb) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(375, 500));
    await windowManager.setMaximumSize(const Size(1440, 900));
  }

  debugPaintBaselinesEnabled = false;
  runApp(const App());
}
