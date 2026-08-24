import 'package:flutter/material.dart';
import 'package:github_release_apk_updater/github_release_apk_updater.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdater {
  static void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colorScheme.error : colorScheme.inverseSurface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
  }

  /// Checks GitHub for a newer release of the app. Shows an update dialog if
  /// one is found, or a "you're up to date" snack-bar otherwise.
  static Future<void> checkForAppUpdates(BuildContext context, {bool isAutomatic = false}) async {
    final colorScheme = Theme.of(context).colorScheme;

    if (!isAutomatic) {
      // Show a loading indicator while we fetch release metadata.
      _showSnackBar(context, 'Checking for updates…');
    }

    try {
      // ── Step 1: fetch latest release metadata from GitHub ─────────────────
      final apiService = GithubApiService();
      final pluginHelper = GithubReleaseApkUpdater();

      final release = await apiService.getLatestGithubAPKRelease(
        ownerGithub: 'abyjays',
        repositoryGithub: 'bus-time-saver',
        apkKeyName: 'app-release.apk',
      );

      if (release == null) {
        if (context.mounted && !isAutomatic) {
          _showSnackBar(context, 'Could not reach GitHub. Check your connection.', isError: true);
        }
        return;
      }

      // ── Step 2: compare remote version with the installed version ─────────
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final hasUpdate = VersionComparator().isNewerVersion(release.version, currentVersion);

      if (!context.mounted) return;

      if (!hasUpdate) {
        if (!isAutomatic) {
          _showSnackBar(context, '✓ You are on the latest version.');
        }
        return;
      }

      // ── Update available — show a dialog ──────────────────────────────────
      final latestTag = release.version;
      final releaseNotes = release.releaseNote.trim().isNotEmpty
          ? release.releaseNote
          : 'No release notes available.';

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _UpdateDialog(
          latestTag: latestTag,
          currentVersion: currentVersion,
          releaseNotes: releaseNotes,
          colorScheme: colorScheme,
          onUpdate: () async {
            Navigator.of(dialogContext).pop();
            if (context.mounted) {
              _showSnackBar(context, 'Downloading update…');
            }
            try {
              // ── Step 3: download APK ────────────────────────────────────────
              final downloader = ApkDownloaderService();
              final filePath = await downloader.downloadAPK(
                release.apkUrl,
                null, // no auth token needed for public repo
                null, // no progress callback
              );

              if (filePath == null) {
                if (context.mounted) {
                  _showSnackBar(
                    context,
                    'Download failed: could not save APK.',
                    isError: true,
                  );
                }
                return;
              }

              // ── Step 4: launch native Android installer ─────────────────────
              await pluginHelper.installApk(filePath);
            } catch (e) {
              if (context.mounted) {
                _showSnackBar(
                  context,
                  'Download failed: $e',
                  isError: true,
                );
              }
            }
          },
        ),
      );
    } catch (e) {
      if (context.mounted && !isAutomatic) {
        _showSnackBar(
          context,
          'Update check failed: $e',
          isError: true,
        );
      }
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({
    required this.latestTag,
    required this.currentVersion,
    required this.releaseNotes,
    required this.colorScheme,
    required this.onUpdate,
  });

  final String latestTag;
  final String currentVersion;
  final String releaseNotes;
  final ColorScheme colorScheme;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          const Text(
            'Update Available',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Version: $currentVersion -> $latestTag',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'What\'s new:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  releaseNotes,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: onUpdate,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Update'),
        ),
      ],
    );
  }
}
