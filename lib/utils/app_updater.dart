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
      final supportedAbis = await pluginHelper.getSupportedAbis();

      final release = await apiService.getLatestGithubAPKRelease(
        ownerGithub: 'abyjays',
        repositoryGithub: 'bus-time-saver',
        apkKeyName: 'app-release.apk',
        supportedAbis: supportedAbis,
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
            _downloadAndInstallWithProgress(context, release.apkUrl, pluginHelper);
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

  static void _downloadAndInstallWithProgress(BuildContext context, String apkUrl, GithubReleaseApkUpdater updater) async {
    ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    // Note: Dio cancel token can be used if your downloader supports it, or manage a cancellation flag:
    bool isCancelled = false;
    
    // Show download progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (progressContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Downloading Update'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, value, _) => LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, value, _) => Text('${(value * 100).toStringAsFixed(0)}% downloaded'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                isCancelled = true;
                Navigator.pop(progressContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Download cancelled.')),
                );
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    try {
      final downloader = ApkDownloaderService();
      final filePath = await downloader.downloadAPK(
        apkUrl,
        null,
        (received, total) {
          if (!isCancelled && total != -1) {
            progressNotifier.value = received / total;
          }
        },
      );

      if (isCancelled) return;

      // Close progress dialog
      if (context.mounted) Navigator.pop(context);

      if (filePath != null) {
        // Keep file available so Android system installer can read it safely, then trigger install
        await updater.installApk(filePath);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download failed. Please try again.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // Close dialog on error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download error. Check your internet connection.')),
        );
      }
      debugPrint('Download error: $e');
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
