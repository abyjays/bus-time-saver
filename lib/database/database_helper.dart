import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  // Singleton instance
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  // Database configuration
  static const String _databaseName = 'bus_time_saver.db';
  static const int databaseVersion = 7;

  // Table name
  static const String tablesBuses = 'buses';

  // Column names
  static const String columnId = 'id';
  static const String columnBusName = 'bus_name';
  static const String columnStartLocation = 'start_location';
  static const String columnDestination = 'destination';
  static const String columnDepartureTime = 'departure_time';
  static const String columnReachingTime = 'reaching_time';
  static const String columnFares = 'fares';
  static const String columnIsFavorite = 'is_favorite';
  static const String columnState = 'state';
  static const String columnStops = 'stops';
  static const String columnBusStop = 'bus_stop';
  static const String columnBusStand = 'bus_stand';

  /// Returns the database instance, initializing it if necessary.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static const _storage = FlutterSecureStorage();

  /// Retrieves the encryption key, generating a new one if it doesn't exist.
  Future<String> getEncryptionKey() async {
    String? key = await _storage.read(key: 'db_encryption_key');
    if (key == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (i) => random.nextInt(256));
      key = base64UrlEncode(bytes);
      await _storage.write(key: 'db_encryption_key', value: key);
    }
    return key;
  }

  /// Opens (or creates) the database at the platform-appropriate path.
  Future<Database> _initDatabase() async {
    // SECURITY: getApplicationDocumentsDirectory() explicitly guarantees a
    // private, sandboxed location on iOS/Android, inaccessible to other apps.
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, _databaseName);
    final key = await getEncryptionKey();

    try {
      return await openDatabase(
        path,
        password: key,
        version: databaseVersion,
        onCreate: _onCreate,
        onUpgrade: onUpgrade,
        onDowngrade: _onDowngrade,
      );
    } catch (e) {
      // Re-throw typed downgrade exceptions immediately — do not treat them
      // as an unencrypted-DB fallback case.
      if (e is DatabaseDowngradeException) rethrow;

      if (e is DatabaseException) {
        // Fallback: If an old, plain-text DB exists, SQLCipher will throw.
        // We delete the old unencrypted DB and create a new encrypted one.
        if (kDebugMode) {
          debugPrint('Failed to open database (possibly unencrypted), recreating: $e');
        }
        await deleteDatabase(path);
        return await openDatabase(
          path,
          password: key,
          version: databaseVersion,
          onCreate: _onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: _onDowngrade,
        );
      }
      rethrow;
    }
  }

  /// Called when the database is created for the first time.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tablesBuses (
        $columnId            INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnBusName       TEXT    NOT NULL,
        $columnStartLocation TEXT    NOT NULL,
        $columnDestination   TEXT    NOT NULL,
        $columnDepartureTime TEXT    NOT NULL,
        $columnReachingTime  TEXT,
        $columnFares         TEXT    NOT NULL,
        $columnIsFavorite    INTEGER NOT NULL DEFAULT 0,
        $columnState         TEXT    NOT NULL DEFAULT '',
        $columnStops         TEXT,
        $columnBusStop       TEXT,
        $columnBusStand      TEXT
      )
    ''');
  }

  /// Called when the database needs to be upgraded to a newer version.
  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 1. Data migrations
    // Version 4: migrate 12-hour AM/PM times to 24-hour HH:mm.
    if (oldVersion < 4) {
      final List<Map<String, dynamic>> allBuses = await db.query(tablesBuses);
      for (final bus in allBuses) {
        final String oldTime = bus[columnDepartureTime] as String? ?? '';
        if (oldTime.contains(' AM') || oldTime.contains(' PM')) {
          final parts = oldTime.split(' ');
          if (parts.length == 2) {
            final timeParts = parts[0].split(':');
            if (timeParts.length == 2) {
              int hour = int.tryParse(timeParts[0]) ?? 0;
              final String minStr = timeParts[1].padLeft(2, '0');
              final isPm = parts[1].toUpperCase() == 'PM';
              
              if (isPm && hour < 12) hour += 12;
              if (!isPm && hour == 12) hour = 0;
              
              final String newTime = '${hour.toString().padLeft(2, '0')}:$minStr';
              
              await db.update(
                tablesBuses,
                {columnDepartureTime: newTime},
                where: '$columnId = ?',
                whereArgs: [bus[columnId]],
              );
            }
          }
        }
      }
    }

    // 2. Dynamic column addition for scalable schema upgrades
    final tableInfo = await db.rawQuery("PRAGMA table_info('$tablesBuses')");
    final existingColumns = tableInfo.map((col) => col['name'] as String).toList();

    // Map of expected columns added after v1 and their SQL definitions
    final expectedColumns = {
      columnIsFavorite: 'INTEGER NOT NULL DEFAULT 0',
      columnState: "TEXT NOT NULL DEFAULT ''",
      columnReachingTime: 'TEXT',
      columnStops: 'TEXT',
      columnBusStop: 'TEXT',
      columnBusStand: 'TEXT',
    };

    for (final entry in expectedColumns.entries) {
      if (!existingColumns.contains(entry.key)) {
        await db.execute('ALTER TABLE $tablesBuses ADD COLUMN ${entry.key} ${entry.value}');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD Operations
  // ---------------------------------------------------------------------------

  /// Inserts a bus record and returns the new row's id.
  Future<int> insertBus(Map<String, dynamic> bus) async {
    final db = await database;
    return await db.insert(
      tablesBuses,
      bus,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns all bus records: favorites first, then ordered by id ASC.
  Future<List<Map<String, dynamic>>> getAllBuses() async {
    final db = await database;
    return await db.query(
      tablesBuses,
      orderBy: '$columnIsFavorite DESC, $columnId ASC',
    );
  }

  /// Returns a single bus record by [id], or null if not found.
  Future<Map<String, dynamic>?> getBusById(int id) async {
    final db = await database;
    final results = await db.query(
      tablesBuses,
      where: '$columnId = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Updates an existing bus record. Returns the number of rows affected.
  Future<int> updateBus(Map<String, dynamic> bus) async {
    final db = await database;
    return await db.update(
      tablesBuses,
      bus,
      where: '$columnId = ?',
      whereArgs: [bus[columnId]],
    );
  }

  /// Deletes a bus record by [id]. Returns the number of rows affected.
  Future<int> deleteBus(int id) async {
    final db = await database;
    return await db.delete(
      tablesBuses,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  /// Toggles the [columnIsFavorite] flag for the bus with [id].
  /// Returns the new favorite state (1 = favorited, 0 = not).
  Future<int> toggleFavorite(int id, {required bool currentlyFavorite}) async {
    final db = await database;
    final newValue = currentlyFavorite ? 0 : 1;
    await db.update(
      tablesBuses,
      {columnIsFavorite: newValue},
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return newValue;
  }

  /// Returns a list of distinct, non-empty past values for a specific column.
  Future<List<String>> getDistinctValues(String columnName) async {
    final db = await database;
    final results = await db.rawQuery(
      'SELECT DISTINCT $columnName FROM $tablesBuses WHERE $columnName IS NOT NULL AND $columnName != ? ORDER BY $columnName ASC',
      [''],
    );
    return results.map((row) => row[columnName] as String).toList();
  }

  /// Returns buses filtered dynamically based on optional multi-criteria parameters.
  Future<List<Map<String, dynamic>>> getAdvancedFilteredBuses({
    List<String>? selectedBuses,
    String? startLoc,
    String? dest,
    String? time,
    String? timeModifier, // 'Exact', 'Before', 'After'
    String? state,
  }) async {
    final db = await database;
    
    final conditions = <String>[];
    final args = <dynamic>[];

    if (selectedBuses != null && selectedBuses.isNotEmpty) {
      final placeholders = List.filled(selectedBuses.length, '?').join(',');
      conditions.add('$columnBusName IN ($placeholders)');
      args.addAll(selectedBuses);
    }
    if (startLoc != null && startLoc.trim().isNotEmpty) {
      conditions.add('$columnStartLocation LIKE ?');
      args.add('%${startLoc.trim()}%');
    }
    if (dest != null && dest.trim().isNotEmpty) {
      conditions.add('$columnDestination LIKE ?');
      args.add('%${dest.trim()}%');
    }
    if (time != null && time.trim().isNotEmpty && timeModifier != null) {
      if (timeModifier == 'Before') {
        conditions.add('$columnDepartureTime < ?');
      } else if (timeModifier == 'After') {
        conditions.add('$columnDepartureTime > ?');
      } else {
        conditions.add('$columnDepartureTime = ?'); // Exact
      }
      args.add(time.trim());
    }
    if (state != null && state.trim().isNotEmpty) {
      conditions.add('$columnState = ?');
      args.add(state.trim());
    }

    final whereClause = conditions.isEmpty ? null : conditions.join(' AND ');
    
    return await db.query(
      tablesBuses,
      where: whereClause,
      whereArgs: args.isEmpty ? null : args,
      orderBy: '$columnIsFavorite DESC, $columnId ASC',
    );
  }

  /// Closes the database connection.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Called when the on-disk database version is **newer** than the app's
  /// [databaseVersion]. This happens when a backup from a newer app version
  /// is restored into an older installation.
  ///
  /// Rather than silently corrupting data or crashing, we surface a clear,
  /// typed exception so the UI can guide the user to update the app.
  static Future<void> _onDowngrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw DatabaseDowngradeException(
      onDiskVersion: oldVersion,
      appVersion: newVersion,
    );
  }
}

// ---------------------------------------------------------------------------
// Typed exception for schema downgrade
// ---------------------------------------------------------------------------

/// Thrown when the app attempts to open a database whose [onDiskVersion] is
/// higher than the app's compiled [appVersion].
///
/// This typically means the user is trying to restore a backup that was
/// created by a **newer** version of the app.
class DatabaseDowngradeException implements Exception {
  DatabaseDowngradeException({
    required this.onDiskVersion,
    required this.appVersion,
  });

  /// The schema version stored in the database file.
  final int onDiskVersion;

  /// The schema version this build of the app supports.
  final int appVersion;

  static const String downgradeMessage =
      'This backup is from a newer version of the app. '
      'Please update your app to import it.';

  @override
  String toString() =>
      'DatabaseDowngradeException: on-disk v$onDiskVersion > app v$appVersion. '
      '$downgradeMessage';
}

