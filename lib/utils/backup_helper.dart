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

  /// Prompts the user to save the database file using the system file picker.
  ///
  /// Throws a [BackupException] on any failure.
  static Future<void> backupDatabase() async {
    try {
      // 1. Safely close the active database.
      // This forces SQLite to checkpoint any pending Write-Ahead Logs (WAL)
      // into the main .db file, ensuring the backup isn't corrupted or incomplete.
      await DatabaseHelper().close();

      final path = await _dbPath();
      final file = File(path);

      if (!await file.exists()) {
        throw BackupException(
          'Database file not found. Try adding a bus first.',
        );
      }

      // 2. Export via System Share Sheet.
      // We use share_plus instead of saving locally so the user can easily
      // push it to Google Drive, Email, or scoped storage safely before uninstalling.
      final xFile = XFile(path, mimeType: 'application/octet-stream');
      
      final result = await Share.shareXFiles(
        [xFile],
        subject: 'Bus Time Saver Backup',
        text: 'Encrypted SQLCipher backup file for Bus Time Saver.',
      );

      if (result.status == ShareResultStatus.dismissed) {
        throw const BackupException('Backup cancelled by user.');
      }

      if (kDebugMode) {
        debugPrint('[BackupHelper] Shared backup file.');
      }
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('Backup failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Opens a file picker so the user can select a `.db` backup file,
  /// then copies it over the live database and resets the connection.
  ///
  /// Returns `true` if the restore completed, `false` if the user cancelled.
  /// Throws a [BackupException] on any other failure.
  static Future<bool> restoreDatabase() async {
    try {
      // 1. Let the user pick a single .db file (v12 API: FilePicker.pickFile)
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Select a Bus Time Saver backup (.db)',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (picked == null) return false; // user cancelled

      final pickedPath = picked.path;
      if (pickedPath == null) {
        throw BackupException('Could not read the selected file path.');
      }

      // 2. Copy the imported file to the active database path.
      await DatabaseHelper().close();
      final destinationPath = await _dbPath();
      final importedFile = File(pickedPath);
      await importedFile.copy(destinationPath);

      final key = await DatabaseHelper().getEncryptionKey();
      Database? newDb;

      try {
        // Attempt to open the database without a password
        newDb = await openDatabase(
          destinationPath,
          singleInstance: false,
        );
        // Test access
        await newDb.rawQuery('SELECT count(*) FROM sqlite_master;');
        
        // If it opens successfully, it is a plain text database. 
        // Immediately run PRAGMA rekey to encrypt it.
        await newDb.execute("PRAGMA rekey = '$key';");
        await newDb.close();
        newDb = null;

        // reopen the database normally with the password
        newDb = await openDatabase(
          destinationPath,
          password: key,
          singleInstance: false,
        );
      } catch (e) {
        // If opening without a password throws an exception, catch it 
        // and try opening the database with the standard app password
        await newDb?.close();
        newDb = null;
        
        try {
          newDb = await openDatabase(
            destinationPath,
            password: key,
            singleInstance: false,
          );
          // Test access
          await newDb.rawQuery('SELECT count(*) FROM sqlite_master;');
        } catch (e2) {
          await newDb?.close();
          throw const BackupException('Invalid database format or wrong encryption key.');
        }
      }

      try {
        // Check and migrate legacy schema versions in the imported DB
        final versionResult = await newDb.rawQuery('PRAGMA user_version;');
        int importedVersion = 0;
        if (versionResult.isNotEmpty) {
          importedVersion = versionResult.first.values.first as int? ?? 0;
        }

        final currentVersion = DatabaseHelper.databaseVersion;
        if (importedVersion < currentVersion) {
          if (kDebugMode) {
            debugPrint('[BackupHelper] Upgrading imported DB from $importedVersion to $currentVersion');
          }
          await DatabaseHelper().onUpgrade(newDb, importedVersion, currentVersion);
          await newDb.execute('PRAGMA user_version = $currentVersion;');
        }

        // Check integrity
        final integrityResult = await newDb.rawQuery('PRAGMA integrity_check;');
        final isOk = integrityResult.isNotEmpty &&
            integrityResult.first.values.first.toString().toLowerCase() == 'ok';
        
        if (!isOk) {
          throw const BackupException('Backup file failed integrity check.');
        }

        // Check schema
        final schemaResult = await newDb.rawQuery("PRAGMA table_info('${DatabaseHelper.tablesBuses}');");
        final columns = schemaResult.map((row) => row['name'] as String).toList();
        
        if (!columns.contains(DatabaseHelper.columnBusName) ||
            !columns.contains(DatabaseHelper.columnStartLocation) ||
            !columns.contains(DatabaseHelper.columnDestination)) {
          throw const BackupException('Backup file is missing required tables or columns.');
        }
      } catch (e) {
        if (e is BackupException) rethrow;
        throw const BackupException('Validation failed.');
      } finally {
        await newDb.close();
      }

      if (kDebugMode) {
        debugPrint('[BackupHelper] Restore complete → $destinationPath');
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
// Custom exception
// ---------------------------------------------------------------------------

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => 'BackupException: $message';
}
