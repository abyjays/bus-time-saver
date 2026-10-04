import 'dart:io';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

/// Static helper for backing up and restoring the SQLite database file.
class BackupHelper {
  BackupHelper._(); // prevent instantiation

  static const String _dbFileName = 'bus_time_saver.db';

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Returns the absolute path to the live database file.
  static Future<String> _dbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _dbFileName);
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  /// Exports an **unencrypted** plain-SQLite copy of the database so it can
  /// survive an uninstall/reinstall (which wipes the secure-storage key).
  ///
  /// Strategy:
  ///  1. Open the live encrypted DB in read-only mode.
  ///  2. ATTACH a temporary file with an empty key (= no encryption).
  ///  3. Run `sqlcipher_export('plaintext')` to copy all pages unencrypted.
  ///  4. DETACH, share the plain file via the system share sheet.
  ///  5. Delete the temp file in a finally block.
  ///
  /// Throws a [BackupException] on any failure.
  static Future<void> backupDatabase() async {
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'bus_time_saver_backup.db');
    Database? encryptedDb;

    try {
      // 1. Ensure a clean temp slot.
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();

      final livePath = await _dbPath();
      if (!await File(livePath).exists()) {
        throw const BackupException(
          'Database file not found. Try adding a bus first.',
        );
      }

      // 2. Open the live encrypted DB (read-only so WAL is not disturbed).
      final liveKey = await DatabaseHelper().getEncryptionKey();
      encryptedDb = await openDatabase(
        livePath,
        password: liveKey,
        singleInstance: false,
        readOnly: true,
      );

      // 3. ATTACH an empty-keyed (plaintext) target file and export.
      await encryptedDb.execute(
        "ATTACH DATABASE ? AS plaintext KEY ''",
        [tempPath],
      );
      await encryptedDb.execute("SELECT sqlcipher_export('plaintext')");
      await encryptedDb.execute('DETACH DATABASE plaintext');

      await encryptedDb.close();
      encryptedDb = null;

      if (!await tempFile.exists()) {
        throw const BackupException('Export produced no output file.');
      }

      // 4. Share the plain SQLite file.
      final xFile = XFile(tempPath, mimeType: 'application/octet-stream');
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          subject: 'Bus Time Saver Backup',
          text: 'Plain SQLite backup for Bus Time Saver. '
              'Import this file to restore your data.',
        ),
      );

      if (result.status == ShareResultStatus.dismissed) {
        throw const BackupException('Backup cancelled by user.');
      }

      if (kDebugMode) {

        debugPrint('[BackupHelper] Shared plain-SQLite backup: $tempPath');
      }
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('Backup failed: $e');
    } finally {
      await encryptedDb?.close();
      // 5. Best-effort cleanup of the temporary plaintext file.
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Opens a file picker so the user can select a `.db` backup file,
  /// then absorbs the plain data into a freshly-encrypted database using
  /// an ATTACH-based migration so the new installation's active key is used.
  ///
  /// Strategy:
  ///  1. Pick the backup file (expected: plain, unencrypted SQLite).
  ///  2. Close the singleton and delete the live DB (+ WAL/SHM siblings).
  ///  3. Open a fresh encrypted DB with the current installation's key.
  ///  4. ATTACH the plain backup file (KEY '' = no password).
  ///  5. Optionally run schema migration on the backup before copying.
  ///  6. Copy all rows via INSERT INTO … SELECT * FROM backup.
  ///  7. DETACH, run integrity check, done.
  ///
  /// Returns `true` if the restore completed, `false` if the user cancelled.
  /// Throws a [BackupException] on any other failure.
  static Future<bool> restoreDatabase() async {
    try {
      // 1. Let the user pick a single .db file.
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Select a Bus Time Saver backup (.db)',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (picked == null) return false; // user cancelled

      final pickedPath = picked.path;
      if (pickedPath == null) {
        throw const BackupException('Could not read the selected file path.');
      }

      // 2. Close the active singleton connection and wipe the live DB so we
      //    can build a fresh encrypted file from scratch.
      await DatabaseHelper().close();
      final destinationPath = await _dbPath();
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$destinationPath$suffix');
        if (await f.exists()) await f.delete();
      }

      // 3. Obtain the active key and open/create a fresh encrypted DB.
      final liveKey = await DatabaseHelper().getEncryptionKey();
      Database? newDb = await openDatabase(
        destinationPath,
        password: liveKey,
        singleInstance: false,
      );

      try {
        // 4. ATTACH the user-selected plain backup (no key).
        await newDb.execute(
          "ATTACH DATABASE ? AS backup KEY ''",
          [pickedPath],
        );

        // Verify the backup contains the expected table before touching anything.
        final tables = await newDb.rawQuery(
          "SELECT name FROM backup.sqlite_master "
          "WHERE type='table' AND name=?",
          [DatabaseHelper.tablesBuses],
        );
        if (tables.isEmpty) {
          await newDb.execute('DETACH DATABASE backup');
          throw const BackupException(
            'Backup file is missing required tables. '
            'Is this a valid Bus Time Saver backup?',
          );
        }

        // 5. Discover which columns actually exist in the backup so that old
        //    backups with fewer columns can be safely absorbed into the current
        //    full schema (avoids column-count mismatch on INSERT … SELECT *).
        final backupTableInfo = await newDb.rawQuery(
          'PRAGMA backup.table_info(${DatabaseHelper.tablesBuses})',
        );
        final backupColumns =
            backupTableInfo.map((r) => r['name'] as String).toList();

        if (kDebugMode) {
          debugPrint('[BackupHelper] Backup columns: $backupColumns');
        }

        // Ensure the target table exists in the fresh encrypted DB with the
        // full current schema.
        await newDb.execute('''
          CREATE TABLE IF NOT EXISTS ${DatabaseHelper.tablesBuses} (
            ${DatabaseHelper.columnId}            INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DatabaseHelper.columnBusName}       TEXT    NOT NULL,
            ${DatabaseHelper.columnStartLocation} TEXT    NOT NULL,
            ${DatabaseHelper.columnDestination}   TEXT    NOT NULL,
            ${DatabaseHelper.columnDepartureTime} TEXT    NOT NULL,
            ${DatabaseHelper.columnReachingTime}  TEXT,
            ${DatabaseHelper.columnFares}         TEXT    NOT NULL,
            ${DatabaseHelper.columnIsFavorite}    INTEGER NOT NULL DEFAULT 0,
            ${DatabaseHelper.columnState}         TEXT    NOT NULL DEFAULT '',
            ${DatabaseHelper.columnStops}         TEXT,
            ${DatabaseHelper.columnBusStop}       TEXT,
            ${DatabaseHelper.columnBusStand}      TEXT
          )
        ''');
        // Clear any rows the openDatabase call might have created.
        await newDb.delete(DatabaseHelper.tablesBuses);

        // 6. Copy rows using an explicit column list so legacy backups with
        //    fewer columns are handled gracefully — missing columns will
        //    receive their DEFAULT values automatically.
        final colList = backupColumns.join(', ');
        await newDb.execute(
          'INSERT INTO ${DatabaseHelper.tablesBuses} ($colList) '
          'SELECT $colList FROM backup.${DatabaseHelper.tablesBuses}',
        );

        // Stamp the schema version on the live encrypted DB.
        await newDb.execute(
          'PRAGMA user_version = ${DatabaseHelper.databaseVersion};',
        );

        // 7. Detach the backup.
        await newDb.execute('DETACH DATABASE backup');

        // Integrity check on the newly populated encrypted DB.
        final integrityResult = await newDb.rawQuery('PRAGMA integrity_check;');
        final isOk =
            integrityResult.isNotEmpty &&
            integrityResult.first.values.first.toString().toLowerCase() == 'ok';
        if (!isOk) {
          throw const BackupException(
            'Restored database failed integrity check.',
          );
        }

        if (kDebugMode) {
          debugPrint('[BackupHelper] Restore complete → $destinationPath');
        }
      } catch (e) {
        await newDb.close();
        newDb = null;
        // Roll back: delete the broken live file so the app can re-create it.
        final broken = File(destinationPath);
        if (await broken.exists()) await broken.delete();
        // Surface downgrade errors with a dedicated typed exception so the UI
        // can show an alert dialog instead of a generic snack bar.
        if (e is DatabaseDowngradeException) throw BackupDowngradeException();
        if (e is BackupException) rethrow;
        throw BackupException('Migration failed: $e');
      } finally {
        await newDb?.close();
      }

      return true;
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('Restore failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Custom exceptions
// ---------------------------------------------------------------------------

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => 'BackupException: $message';
}

/// A specialised [BackupException] thrown when the user attempts to import a
/// backup whose schema version is newer than what this build of the app
/// supports. The UI should present this as a blocking alert dialog, not a
/// transient snack bar, because the fix requires the user to take an action
/// (update the app) before retrying.
class BackupDowngradeException extends BackupException {
  BackupDowngradeException()
      : super(DatabaseDowngradeException.downgradeMessage);

}
