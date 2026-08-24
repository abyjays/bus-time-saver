import 'dart:io';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
      final path = await _dbPath();
      final file = File(path);

      if (!await file.exists()) {
        throw BackupException(
          'Database file not found. Try adding a bus first.',
        );
      }

      final bytes = await file.readAsBytes();

      // In file_picker v12, saveFile() takes the bytes and filename directly,
      // and returns a Uri? indicating where it was saved.
      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Save Bus Time Saver Backup',
        fileName: _dbFileName,
        bytes: bytes,
        mimeType: 'application/octet-stream',
      );

      if (savedUri == null) {
        throw const BackupException('Backup cancelled by user.');
      }

      if (kDebugMode) {
        debugPrint('[BackupHelper] Saved backup to: $savedUri');
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

      // 2. Copy to a temporary sandbox location to avoid mutating user files or locking live DB
      final dir = await getApplicationDocumentsDirectory();
      final tempPath = p.join(dir.path, 'temp_restore.db');
      final tempFile = await File(pickedPath).copy(tempPath);

      // 3. Pre-Restore Validation
      Database? tempDb;
      try {
        final key = await DatabaseHelper().getEncryptionKey();
        tempDb = await openDatabase(
          tempPath,
          password: key,
          readOnly: true,
          singleInstance: false,
        );

        // Check integrity
        final integrityResult = await tempDb.rawQuery('PRAGMA integrity_check;');
        final isOk = integrityResult.isNotEmpty &&
            integrityResult.first.values.first.toString().toLowerCase() == 'ok';
        
        if (!isOk) {
          throw const BackupException('Backup file failed integrity check.');
        }

        // Check schema
        final schemaResult = await tempDb.rawQuery("PRAGMA table_info('${DatabaseHelper.tablesBuses}');");
        final columns = schemaResult.map((row) => row['name'] as String).toList();
        
        if (!columns.contains(DatabaseHelper.columnBusName) ||
            !columns.contains(DatabaseHelper.columnStartLocation) ||
            !columns.contains(DatabaseHelper.columnDestination)) {
          throw const BackupException('Backup file is missing required tables or columns.');
        }

      } catch (e) {
        // Clean up temp file on failure
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (e is BackupException) rethrow;
        throw const BackupException('Invalid database file format.');
      } finally {
        await tempDb?.close();
      }

      // 4. Validation passed, close live DB and overwrite
      await DatabaseHelper().close();
      final destinationPath = await _dbPath();
      await tempFile.copy(destinationPath);
      
      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
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
