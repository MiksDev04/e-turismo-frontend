import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// ---------------------------------------------------------------------------
/// LocalDatabase
/// ---------------------------------------------------------------------------
/// Singleton that owns the SQLite connection for the entire app.
///
/// Usage:
///   final db = await LocalDatabase.instance.database;
///   await db.insert(LocalDatabase.tableLocalProfiles, {...});
///
/// Versioning:
///   Bump [_kDbVersion] and add a block inside [_onUpgrade] whenever the
///   schema changes.  Never alter existing [_onCreate] SQL — migrations only.
/// ---------------------------------------------------------------------------
class LocalDatabase {
  LocalDatabase._internal();

  static final LocalDatabase instance = LocalDatabase._internal();

  static Database? _db;

  // ── file name ──────────────────────────────────────────────────────────────
  static const String _kDbName = 'tourism_local.db';

  // ── schema version ─────────────────────────────────────────────────────────
  static const int _kDbVersion = 3;

  // ── table names ────────────────────────────────────────────────────────────
  static const String tableLocalProfiles   = 'local_profiles';
  static const String tableLocalBusinesses = 'local_businesses';
  static const String tableGuestRecords    = 'local_guest_records';
  static const String tableGuestRecordRooms = 'local_guest_record_rooms';
  static const String tableLocalRooms      = 'local_rooms';

  // ── sync status constants ──────────────────────────────────────────────────
  /// Record exists on Backend and matches local copy.
  static const String syncSynced        = 'synced';
  /// Created offline, not yet pushed to Backend.
  static const String syncPendingCreate = 'pending_create';
  /// Edited offline, not yet pushed to Backend.
  static const String syncPendingUpdate = 'pending_update';

  // ── database accessor ──────────────────────────────────────────────────────
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  // ── init ───────────────────────────────────────────────────────────────────
  // NOTE: We deliberately do NOT use sqflite's getDatabasesPath() here.
  // On desktop (sqflite_common_ffi), that defaults to a path *relative to
  // the current working directory* (.dart_tool/sqflite_common_ffi/databases).
  // That works fine when running via `flutter run` from the project folder,
  // but breaks once installed to C:\Program Files\... , which is a
  // UAC-protected folder standard Windows accounts can't write into.
  // getApplicationSupportDirectory() resolves to a proper per-user,
  // always-writable folder (under %APPDATA% on Windows) instead.
  Future<Database> _initDatabase() async {
    final supportDir = await getApplicationSupportDirectory();
    final fullPath = join(supportDir.path, _kDbName);

    return openDatabase(
      fullPath,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: onDatabaseDowngradeDelete,
      // Enforce foreign-key constraints on every connection.
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  /// Returns the full filesystem path to the SQLite database file.
  /// Useful for logging or diagnostics on desktop platforms.
  Future<String> getDatabaseFilePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return join(supportDir.path, _kDbName);
  }

  // ── onCreate — full schema at current version ──────────────────────────────
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute(_sqlCreateLocalProfiles);
      await txn.execute(_sqlCreateLocalBusinesses);
      await txn.execute(_sqlCreateGuestRecords);
      await txn.execute(_sqlCreateLocalRooms);
      await txn.execute(_sqlCreateGuestRecordRooms);

      await txn.execute(_sqlIndexGuestRecordsBusiness);
      await txn.execute(_sqlIndexGuestRecordsSyncStatus);
      await txn.execute(_sqlIndexLocalRoomsBusiness);
      await txn.execute(_sqlIndexGuestRecordRoomsRecord);
    });
  }

  // ── onUpgrade — migration blocks for version bumps ────────────────────────
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: Replace rooms_occupied + guest_breakdowns with lead guest fields,
    //          add local_rooms table, store room_ids as JSON text.
    if (oldVersion < 2) {
      // 1. Create the new rooms table
      await db.execute(_sqlCreateLocalRooms);
      await db.execute(_sqlIndexLocalRoomsBusiness);

      // 2. Migrate guest_records: drop old columns, add new ones
      // SQLite doesn't support DROP COLUMN before 3.35.0, so we recreate.
      // Check if the old columns exist before attempting migration.
      final tableInfo = await db.rawQuery("PRAGMA table_info($tableGuestRecords)");
      final columnNames = tableInfo.map((c) => c['name'] as String).toSet();

      if (columnNames.contains('rooms_occupied')) {
        // Recreate guest_records with new schema
        await db.execute('ALTER TABLE $tableGuestRecords RENAME TO ${tableGuestRecords}_old');
        await db.execute(_sqlCreateGuestRecords);
        await db.execute('''
          INSERT INTO $tableGuestRecords (
            id, business_id, check_in, check_out, total_guests,
            purpose_of_visit, transportation_mode,
            status, is_deleted, created_at, sync_status, local_updated_at
          )
          SELECT id, business_id, check_in, check_out, total_guests,
                 purpose_of_visit, transportation_mode,
                 status, is_deleted, created_at, sync_status, local_updated_at
          FROM ${tableGuestRecords}_old
        ''');
        await db.execute('DROP TABLE ${tableGuestRecords}_old');
      }

      // 3. Drop old guest_breakdowns table if it exists
      await db.execute('DROP TABLE IF EXISTS local_guest_breakdowns');
    }

    // v2 → v3: Add capacity to local_rooms, length_of_stay to guest_records,
    //          create guest_record_rooms junction table.
    if (oldVersion < 3) {
      // 1. Add capacity column to local_rooms if missing
      final roomsInfo = await db.rawQuery("PRAGMA table_info($tableLocalRooms)");
      final roomsCols = roomsInfo.map((c) => c['name'] as String).toSet();
      if (!roomsCols.contains('capacity')) {
        await db.execute("ALTER TABLE $tableLocalRooms ADD COLUMN capacity INTEGER NOT NULL DEFAULT 1");
      }

      // 2. Add length_of_stay column to guest_records if missing
      final grInfo = await db.rawQuery("PRAGMA table_info($tableGuestRecords)");
      final grCols = grInfo.map((c) => c['name'] as String).toSet();
      if (!grCols.contains('length_of_stay')) {
        await db.execute("ALTER TABLE $tableGuestRecords ADD COLUMN length_of_stay INTEGER NOT NULL DEFAULT 1");
      }

      // 3. Create junction table for guest record ↔ room
      await db.execute(_sqlCreateGuestRecordRooms);
      await db.execute(_sqlIndexGuestRecordRoomsRecord);

      // 4. Drop legacy breakdowns table if still around
      await db.execute('DROP TABLE IF EXISTS local_guest_breakdowns');
    }
  }

  // ── helper: close (mainly for tests) ──────────────────────────────────────
  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  // ── helper: delete database (dev/debug only) ───────────────────────────────
  Future<void> deleteDatabaseFile() async {
    final supportDir = await getApplicationSupportDirectory();
    final fullPath = join(supportDir.path, _kDbName);
    await deleteDatabase(fullPath);
    _db = null;
  }

  // ---------------------------------------------------------------------------
  // SQL — table definitions
  // ---------------------------------------------------------------------------

  /// Cached login credentials.
  /// One row per staff account that has ever logged in on this device.
  /// password_hash = SHA-256( password + userId ) — never stored in plain text.
  static const String _sqlCreateLocalProfiles = '''
    CREATE TABLE $tableLocalProfiles (
      id            TEXT PRIMARY KEY,
      username      TEXT NOT NULL,
      full_name     TEXT,
      email         TEXT,
      phone         TEXT,
      role          TEXT,
      password_hash TEXT NOT NULL
    )
  ''';

  /// Cached business data for the logged-in profile.
  /// Refreshed from Backend on every successful online login.
  static const String _sqlCreateLocalBusinesses = '''
    CREATE TABLE $tableLocalBusinesses (
      id                  TEXT PRIMARY KEY,
      profile_id          TEXT NOT NULL,
      business_name       TEXT,
      status              TEXT,
      permit_number       TEXT,
      registration_number TEXT,
      street              TEXT,
      total_rooms         INTEGER,
      region              TEXT,
      city_municipality   TEXT,
      province            TEXT,
      barangay            TEXT,
      tradename           TEXT,
      business_line       TEXT,
      owner_first_name    TEXT,
      owner_last_name     TEXT,
      owner_middle_name   TEXT,
      business_type       TEXT,
      FOREIGN KEY (profile_id) REFERENCES $tableLocalProfiles (id)
        ON DELETE CASCADE
    )
  ''';

  /// Guest records with sync tracking and lead guest demographics.
  /// sync_status drives the push phase of SyncService.
  /// All datetimes are stored as ISO 8601 strings (UTC).
  /// Room assignments live in the junction table local_guest_record_rooms.
  static const String _sqlCreateGuestRecords = '''
    CREATE TABLE $tableGuestRecords (
      id                      TEXT PRIMARY KEY,
      business_id             TEXT NOT NULL,
      check_in                TEXT NOT NULL,
      check_out               TEXT NOT NULL,
      length_of_stay          INTEGER NOT NULL DEFAULT 1,
      total_guests            INTEGER NOT NULL,
      purpose_of_visit        TEXT NOT NULL,
      transportation_mode     TEXT NOT NULL,
      lead_country            TEXT,
      lead_municipality       TEXT,
      lead_province           TEXT,
      lead_nationality        TEXT,
      lead_philippines_region TEXT,
      lead_is_overseas        INTEGER NOT NULL DEFAULT 0,
      lead_birthdate          TEXT,
      lead_sex                TEXT,
      status                  TEXT NOT NULL DEFAULT 'active',
      is_deleted              INTEGER NOT NULL DEFAULT 0,
      created_at              TEXT,
      sync_status             TEXT NOT NULL DEFAULT '$syncSynced',
      local_updated_at        TEXT,
      FOREIGN KEY (business_id) REFERENCES $tableLocalBusinesses (id)
        ON DELETE CASCADE
    )
  ''';

  /// Cached rooms for a business, used for offline room selection.
  /// Refreshed from Backend when online.
  static const String _sqlCreateLocalRooms = '''
    CREATE TABLE $tableLocalRooms (
      id            TEXT PRIMARY KEY,
      business_id   TEXT NOT NULL,
      room_number   TEXT NOT NULL,
      capacity      INTEGER NOT NULL DEFAULT 1,
      room_status   TEXT NOT NULL DEFAULT 'vacant'
    )
  ''';

  /// Junction table linking guest records to rooms (matches backend schema).
  /// Populated during sync pull; written alongside local_guest_records on save.
  static const String _sqlCreateGuestRecordRooms = '''
    CREATE TABLE $tableGuestRecordRooms (
      id                TEXT PRIMARY KEY,
      guest_record_id   TEXT NOT NULL,
      room_id           TEXT NOT NULL,
      created_at        TEXT,
      FOREIGN KEY (guest_record_id) REFERENCES $tableGuestRecords (id) ON DELETE CASCADE,
      FOREIGN KEY (room_id) REFERENCES $tableLocalRooms (id) ON DELETE RESTRICT
    )
  ''';

  // ---------------------------------------------------------------------------
  // SQL — indexes
  // ---------------------------------------------------------------------------

  /// Fast look-up of all guest records belonging to a business.
  static const String _sqlIndexGuestRecordsBusiness = '''
    CREATE INDEX idx_guest_records_business_id
      ON $tableGuestRecords (business_id)
  ''';

  /// Fast look-up of all unsynced records during the push phase.
  static const String _sqlIndexGuestRecordsSyncStatus = '''
    CREATE INDEX idx_guest_records_sync_status
      ON $tableGuestRecords (sync_status)
  ''';

  /// Fast look-up of all rooms belonging to a business.
  static const String _sqlIndexLocalRoomsBusiness = '''
    CREATE INDEX idx_local_rooms_business_id
      ON $tableLocalRooms (business_id)
  ''';

  /// Fast look-up of room links for a guest record.
  static const String _sqlIndexGuestRecordRoomsRecord = '''
    CREATE INDEX idx_guest_record_rooms_record_id
      ON $tableGuestRecordRooms (guest_record_id)
  ''';
}
