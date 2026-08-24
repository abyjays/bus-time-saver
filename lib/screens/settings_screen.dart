import 'package:flutter/material.dart';
import '../main.dart' show BusTimeSaverApp;
import '../utils/backup_helper.dart';
import '../utils/app_updater.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showSnackBar(BuildContext context, String message,
      {bool isError = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? colorScheme.error : colorScheme.inverseSurface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeNotifier = BusTimeSaverApp.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Display ─────────────────────────────────────────────────────
          _SectionLabel(label: 'Display', colorScheme: colorScheme),
          const SizedBox(height: 8),
          Card(
            key: const Key('settings_appearance_card'),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(100),
              ),
            ),
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SwitchListTile(
                key: const Key('settings_dark_mode_tile'),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    themeNotifier.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Dark Mode',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  themeNotifier.isDark
                      ? 'Dark theme enabled'
                      : 'Light theme enabled',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: themeNotifier.isDark,
                onChanged: (_) => themeNotifier.toggleTheme(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Storage ─────────────────────────────────────────────────────
          _SectionLabel(label: 'Storage', colorScheme: colorScheme),
          const SizedBox(height: 8),
          Card(
            key: const Key('settings_storage_card'),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(100),
              ),
            ),
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  // ── Backup ────────────────────────────────────────────
                  ListTile(
                    key: const Key('settings_backup_tile'),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.backup_rounded,
                        color: colorScheme.onSecondaryContainer,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Backup Database',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Export and share a copy of your data',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.outlineVariant,
                    ),
                    onTap: () async {
                      try {
                        await BackupHelper.backupDatabase();
                        if (context.mounted) {
                          _showSnackBar(
                              context, 'Backup shared successfully.');
                        }
                      } on BackupException catch (e) {
                        if (context.mounted) {
                          _showSnackBar(context, e.message, isError: true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          _showSnackBar(context, 'Unexpected error: $e',
                              isError: true);
                        }
                      }
                    },
                  ),

                  Divider(
                    height: 1,
                    indent: 60,
                    endIndent: 16,
                    color: colorScheme.outlineVariant.withAlpha(80),
                  ),

                  // ── Restore ───────────────────────────────────────────
                  ListTile(
                    key: const Key('settings_restore_tile'),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(16),
                      ),
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.restore_rounded,
                        color: colorScheme.onTertiaryContainer,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Restore Database',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Import a previously exported backup',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.outlineVariant,
                    ),
                    onTap: () async {
                      try {
                        final restored =
                            await BackupHelper.restoreDatabase();
                        if (restored && context.mounted) {
                          _showSnackBar(
                            context,
                            'Database restored. Restart the app to see changes.',
                          );
                        }
                      } on BackupException catch (e) {
                        if (context.mounted) {
                          _showSnackBar(context, e.message, isError: true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          _showSnackBar(context, 'Unexpected error: $e',
                              isError: true);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Updates ─────────────────────────────────────────────────────
          _SectionLabel(label: 'Updates', colorScheme: colorScheme),
          const SizedBox(height: 8),
          Card(
            key: const Key('settings_updates_card'),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(100),
              ),
            ),
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                key: const Key('settings_check_update_tile'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Check for Updates',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Download the latest version from GitHub',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.outlineVariant,
                ),
                onTap: () => AppUpdater.checkForAppUpdates(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.colorScheme});

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

