import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  // Keep the native splash visible until HomeScreen calls remove().
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // Load environment variables from the bundled .env asset.
  await dotenv.load(fileName: '.env');
  runApp(const BusTimeSaverApp());
}

// ---------------------------------------------------------------------------
// Theme state manager
// ---------------------------------------------------------------------------

const String _kThemePrefKey = 'theme_mode'; // key used in SharedPreferences

/// A [ChangeNotifier] that owns the current [ThemeMode], persisting it to
/// [SharedPreferences] so the user's choice survives app restarts.
class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier._();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  // ---------------------------------------------------------------------------
  // Factory – load persisted preference before first paint
  // ---------------------------------------------------------------------------

  /// Creates a [ThemeNotifier] whose initial [themeMode] is loaded from
  /// [SharedPreferences]. Call this once from [main] or [initState].
  static Future<ThemeNotifier> create() async {
    final notifier = ThemeNotifier._();
    await notifier._loadTheme();
    return notifier;
  }

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemePrefKey);
    if (saved == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }
    // No notifyListeners() here – called before the widget tree exists.
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePrefKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    _saveTheme(_themeMode); // fire-and-forget persist
  }
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class BusTimeSaverApp extends StatefulWidget {
  const BusTimeSaverApp({super.key});

  @override
  State<BusTimeSaverApp> createState() => _BusTimeSaverAppState();

  /// Allows any descendant to reach the [ThemeNotifier] without a package
  /// dependency by walking up the element tree.
  static ThemeNotifier of(BuildContext context) {
    final state =
        context.findAncestorStateOfType<_BusTimeSaverAppState>();
    assert(state != null, 'No BusTimeSaverApp found in widget tree');
    return state!._themeNotifier ?? ThemeNotifier._();
  }
}

class _BusTimeSaverAppState extends State<BusTimeSaverApp> {
  // Seed colour used for both light and dark colour schemes.
  static const Color _seedColor = Color(0xFF1565C0); // rich indigo-blue

  /// Null until [ThemeNotifier.create()] resolves; the app shows nothing
  /// (handled by [FutureBuilder]) while loading.
  ThemeNotifier? _themeNotifier;

  @override
  void initState() {
    super.initState();
    _initTheme();
  }

  Future<void> _initTheme() async {
    final notifier = await ThemeNotifier.create();
    notifier.addListener(() => setState(() {}));
    if (mounted) {
      setState(() => _themeNotifier = notifier);
    }
  }

  @override
  void dispose() {
    _themeNotifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While the theme preference is loading, render a plain dark/light
    // splash so the screen isn't blank.
    final notifier = _themeNotifier;
    if (notifier == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox.shrink(),
        ),
      );
    }

    return MaterialApp(
      title: 'Bus Time Saver',
      debugShowCheckedModeBanner: false,

      themeMode: notifier.themeMode,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),

      home: const SplashScreen(),
    );
  }
}
