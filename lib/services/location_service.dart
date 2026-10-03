import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Provides live location suggestions via the Photon (OpenStreetMap) API.
///
/// The API URL is loaded from the `.env` file using [flutter_dotenv].
/// All network errors are swallowed and an empty list is returned, so callers
/// can safely fall back to offline suggestions without any extra error handling.
class LocationService {
  LocationService._(); // prevent instantiation — all methods are static

  /// Fetches a list of location display names matching [query].
  ///
  /// [state] is appended to the query to bias results toward a specific region.
  /// Returns an empty list if the query is too short or any network error occurs.
  static Future<List<String>> fetchSuggestions(
    String query, {
    String state = '',
  }) async {
    try {
      // Default to the public Photon endpoint if the env variable is missing
      final baseUrl = dotenv.env['MAPS_API_URL'] ?? 'https://photon.komoot.io/api/';

      // Safely combine query with optional state. Ensure 'null' is never appended.
      final cleanQuery = query.trim();
      final cleanState = state.trim();
      final hasStateFilter =
          cleanState.isNotEmpty && cleanState.toLowerCase() != 'null';

      // Append state to the search text to bias ranking toward the chosen region.
      final searchText = hasStateFilter ? '$cleanQuery $cleanState' : cleanQuery;

      final url = Uri.parse('$baseUrl?q=${Uri.encodeQueryComponent(searchText)}&limit=10');
      debugPrint('Requesting: $url');
      final response = await http.get(url, headers: {'User-Agent': 'BusTimeSaverApp/1.0'}).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '[LocationService] Photon API error ${response.statusCode}: ${response.body}',
          );
        }
        throw Exception('API Error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];

      final results = <String>{};
      for (final f in features) {
        final props = (f['properties'] ?? {}) as Map<String, dynamic>;

        // ── State filter ──────────────────────────────────────────────────────
        // When the caller has selected a specific state, only accept features
        // whose 'state' property matches that state (case-insensitive).
        // Features with no state info from the API are also excluded to prevent
        // ambiguous cross-country results from slipping through.
        if (hasStateFilter) {
          final propState = (props['state'] ?? '').toString().trim();
          if (propState.isEmpty ||
              propState.toLowerCase() != cleanState.toLowerCase()) {
            debugPrint(
              '[LocationService] Skipping "${props['name']}" — state "$propState" != "$cleanState"',
            );
            continue;
          }
        }

        final name = (props['name'] ?? props['city'] ?? 'Unknown location').toString();
        final propState = (props['state'] ?? '').toString().trim();
        final country = (props['country'] ?? '').toString().trim();

        // Build the display string, filtering out empty strings and duplicates
        final parts = <String>[name];
        if (propState.isNotEmpty && propState != name) parts.add(propState);
        if (country.isNotEmpty && parts.length < 3) parts.add(country);

        final display = parts.join(', ');
        if (display.isNotEmpty) results.add(display);
      }

      debugPrint('[LocationService] ${results.length} results after state filter (state: "$cleanState")');
      return results.toList();
    } catch (e) {
      debugPrint('Location fetching error: $e');
      return [];
    }
  }
}
