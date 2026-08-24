import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// A singleton service that exposes the device's real-time network status.
///
/// Usage:
/// ```dart
/// final service = ConnectivityService();
/// final isOnline = await service.isOnline();
/// service.onlineStream.listen((online) { ... });
/// ```
class ConnectivityService {
  // Singleton ─────────────────────────────────────────────────────────────────
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Emits `true` when the device has network access, `false` when it does not.
  ///
  /// The stream is backed by [Connectivity.onConnectivityChanged] and mapped to
  /// a simple boolean, making it trivial to consume in a [StatefulWidget].
  Stream<bool> get onlineStream => _connectivity.onConnectivityChanged.map(
        (results) => _resultsAreOnline(results),
      );

  /// One-shot check of the current connectivity state.
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _resultsAreOnline(results);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  bool _resultsAreOnline(List<ConnectivityResult> results) {
    // Consider the device online if ANY interface reports a real connection.
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );
  }
}
