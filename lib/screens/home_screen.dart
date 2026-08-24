import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../database/database_helper.dart';
import '../main.dart' show BusTimeSaverApp;
import '../services/connectivity_service.dart';
import '../widgets/custom_fields.dart';
import 'add_bus_screen.dart';
import 'settings_screen.dart';
import '../utils/app_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final SearchController _materialSearchController = SearchController();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Dedicated FocusNode for the search field to allow programmatic unfocusing.
  final FocusNode _searchFocusNode = FocusNode();

  /// Real-time network status — `true` = online, `false` = offline.
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  /// The future driving the main bus list. Reassigned to trigger a rebuild.
  late Future<List<Map<String, dynamic>>> _busListFuture;

  /// Changing this key forces [_BusResultsList] (and its [FutureBuilder]) to
  /// be completely torn down and rebuilt, guaranteeing a fresh DB fetch.
  Key _listKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _busListFuture = _dbHelper.getAllBuses();
    // Dismiss the native splash now that the home screen is ready to paint.
    FlutterNativeSplash.remove();
    // Seed the initial connectivity state, then listen for changes.
    _initConnectivity();
    _checkAutoUpdate();
  }

  Future<void> _checkAutoUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final autoUpdate = prefs.getBool('auto_update') ?? true;
    if (autoUpdate && mounted) {
      AppUpdater.checkForAppUpdates(context, isAutomatic: true);
    }
  }

  Future<void> _initConnectivity() async {
    final online = await ConnectivityService().isOnline();
    if (mounted) setState(() => _isOnline = online);
    _connectivitySub = ConnectivityService().onlineStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  // Sort State
  String _currentSort = 'Time';

  // Advanced Filter State
  List<String> _filterSelectedBuses = [];
  String? _filterStartLoc;
  String? _filterDest;
  String? _filterTime;
  String _filterTimeModifier = 'Exact'; // Default
  String? _filterState;

  bool get _hasFilters =>
      _filterSelectedBuses.isNotEmpty ||
      (_filterStartLoc?.isNotEmpty ?? false) ||
      (_filterDest?.isNotEmpty ?? false) ||
      (_filterTime?.isNotEmpty ?? false) ||
      (_filterState?.isNotEmpty ?? false);

  /// Replaces [_busListFuture] with a fresh query and rotates [_listKey] to
  /// physically rebuild the [FutureBuilder], preventing stale-cache issues.
  void _refreshBusList() {
    if (!mounted) return;
    setState(() {
      Future<List<Map<String, dynamic>>> future;
      if (_hasFilters) {
        future = _dbHelper.getAdvancedFilteredBuses(
          selectedBuses: _filterSelectedBuses,
          startLoc: _filterStartLoc,
          dest: _filterDest,
          time: _filterTime,
          timeModifier: _filterTimeModifier,
          state: _filterState,
        );
      } else {
        future = _dbHelper.getAllBuses();
      }
      
      _busListFuture = future.then((buses) {
        final sortedList = List<Map<String, dynamic>>.from(buses);
        if (_currentSort == 'Time') {
          sortedList.sort((a, b) => (a[DatabaseHelper.columnDepartureTime] as String? ?? '').compareTo(b[DatabaseHelper.columnDepartureTime] as String? ?? ''));
        } else if (_currentSort == 'A-Z') {
          sortedList.sort((a, b) => (a[DatabaseHelper.columnBusName] as String? ?? '').compareTo(b[DatabaseHelper.columnBusName] as String? ?? ''));
        } else if (_currentSort == 'Z-A') {
          sortedList.sort((a, b) => (b[DatabaseHelper.columnBusName] as String? ?? '').compareTo(a[DatabaseHelper.columnBusName] as String? ?? ''));
        } else if (_currentSort == 'Date Added') {
          sortedList.sort((a, b) => (b[DatabaseHelper.columnId] as int? ?? 0).compareTo(a[DatabaseHelper.columnId] as int? ?? 0));
        }
        return sortedList;
      });
      
      _listKey = UniqueKey();
    });
  }

  void _showFilterSheet() async {
    final colorScheme = Theme.of(context).colorScheme;
    final distinctBuses = await _dbHelper.getDistinctValues(DatabaseHelper.columnBusName);
    final distinctStarts = await _dbHelper.getDistinctValues(DatabaseHelper.columnStartLocation);
    final distinctDests = await _dbHelper.getDistinctValues(DatabaseHelper.columnDestination);

    // Create local copies of filter state for the sheet
    List<String> tempSelectedBuses = List.from(_filterSelectedBuses);
    String tempStart = _filterStartLoc ?? '';
    String tempDest = _filterDest ?? '';
    String tempState = _filterState ?? '';
    String? tempTime = _filterTime;
    String tempTimeModifier = _filterTimeModifier;

    final startController = TextEditingController(text: tempStart);
    final destController = TextEditingController(text: tempDest);
    final startFocus = FocusNode();
    final destFocus = FocusNode();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Advanced Filters',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select Buses',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: -4,
                        children: distinctBuses.map((bus) {
                          final isSelected = tempSelectedBuses.contains(bus);
                          return FilterChip(
                            label: Text(bus),
                            selected: isSelected,
                            onSelected: (selected) {
                              setModalState(() {
                                if (selected) {
                                  tempSelectedBuses.add(bus);
                                } else {
                                  tempSelectedBuses.remove(bus);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (distinctBuses.isEmpty)
                        const Text('No buses available to filter by.'),
                      const SizedBox(height: 24),
                      Text(
                        'Locations',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LiveLocationField(
                        controller: startController,
                        focusNode: startFocus,
                        label: 'Start Location',
                        hint: 'Any',
                        icon: Icons.my_location_rounded,
                        colorScheme: colorScheme,
                        isOnline: _isOnline,
                        stateHint: '',
                        offlineSuggestions: distinctStarts,
                      ),
                      const SizedBox(height: 12),
                      LiveLocationField(
                        controller: destController,
                        focusNode: destFocus,
                        label: 'Destination',
                        hint: 'Any',
                        icon: Icons.location_on_rounded,
                        colorScheme: colorScheme,
                        isOnline: _isOnline,
                        stateHint: '',
                        offlineSuggestions: distinctDests,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: tempState.isNotEmpty && indianStates.contains(tempState) ? tempState : null,
                        decoration: InputDecoration(
                          labelText: 'State',
                          hintText: 'Any',
                          prefixIcon: Icon(Icons.map_outlined, color: colorScheme.primary),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withAlpha(100),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        items: [
                          const DropdownMenuItem<String>(value: '', child: Text('Any')),
                          ...indianStates.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                        ],
                        onChanged: (val) {
                          setModalState(() {
                            tempState = val ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Departure Time',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final initial = tempTime != null
                                    ? TimeOfDay(
                                        hour: int.parse(tempTime!.split(':')[0]),
                                        minute: int.parse(tempTime!.split(':')[1]),
                                      )
                                    : TimeOfDay.now();
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: initial,
                                  builder: (context, child) => MediaQuery(
                                    data: MediaQuery.of(context)
                                        .copyWith(alwaysUse24HourFormat: false),
                                    child: child!,
                                  ),
                                );
                                if (picked != null) {
                                  setModalState(() {
                                    final h = picked.hour.toString().padLeft(2, '0');
                                    final m = picked.minute.toString().padLeft(2, '0');
                                    tempTime = '$h:$m';
                                  });
                                }
                              },
                              icon: const Icon(Icons.access_time_rounded),
                              label: Text(tempTime != null
                                  ? () {
                                      final parts = tempTime!.split(':');
                                      int h = int.parse(parts[0]);
                                      final m = parts[1];
                                      final p = h >= 12 ? 'PM' : 'AM';
                                      if (h > 12) h -= 12;
                                      if (h == 0) h = 12;
                                      return '$h:$m $p';
                                    }()
                                  : 'Select Time'),
                            ),
                          ),
                          if (tempTime != null)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                setModalState(() {
                                  tempTime = null;
                                });
                              },
                            ),
                        ],
                      ),
                      if (tempTime != null) ...[
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'Exact', label: Text('Exact')),
                            ButtonSegment(value: 'Before', label: Text('Before')),
                            ButtonSegment(value: 'After', label: Text('After')),
                          ],
                          selected: {tempTimeModifier},
                          onSelectionChanged: (set) {
                            setModalState(() {
                              tempTimeModifier = set.first;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  tempSelectedBuses.clear();
                                  startController.clear();
                                  destController.clear();
                                  tempTime = null;
                                  tempTimeModifier = 'Exact';
                                  tempState = '';
                                });
                              },
                              child: const Text('Clear All'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _filterSelectedBuses = tempSelectedBuses;
                                  _filterStartLoc = startController.text;
                                  _filterDest = destController.text;
                                  _filterTime = tempTime;
                                  _filterTimeModifier = tempTimeModifier;
                                  _filterState = tempState;
                                });
                                _refreshBusList();
                                Navigator.pop(context);
                              },
                              child: const Text('Apply Filters'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    _materialSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeNotifier = BusTimeSaverApp.of(context);

    return Scaffold(
      key: _scaffoldKey,
      // ── Drawer open/close callback — unfocus keyboard when drawer opens ──
      onDrawerChanged: (isOpened) {
        if (isOpened) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      // ── AppBar ────────────────────────────────────────────────────────────
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus_rounded,
                color: colorScheme.primary, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Bus Time Saver',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // ── Network status indicator ─────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _isOnline
                ? Tooltip(
                    key: const ValueKey('online'),
                    message: 'Online',
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.green.withAlpha(80),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_rounded,
                              size: 14, color: Colors.green[600]),
                          const SizedBox(width: 4),
                          Text(
                            'Online',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Tooltip(
                    key: const ValueKey('offline'),
                    message: 'Offline — no internet connection',
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.outline.withAlpha(80),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              size: 14,
                              color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            'Offline',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          // ── Theme toggle button ──────────────────────────────────────────
          Tooltip(
            message: themeNotifier.isDark
                ? 'Switch to Light Mode'
                : 'Switch to Dark Mode',
            child: IconButton(
              key: const Key('theme_toggle_button'),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  themeNotifier.isDark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  key: ValueKey(themeNotifier.isDark),
                  color: colorScheme.primary,
                ),
              ),
              onPressed: themeNotifier.toggleTheme,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),

      // ── Body ─────────────────────────────────────────────────────────────
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────────────
          _BusSearchBar(
            controller: _materialSearchController,
            focusNode: _searchFocusNode,
            colorScheme: colorScheme,
            dbHelper: _dbHelper,
            onRefresh: _refreshBusList,
            onFilterPressed: _showFilterSheet,
            hasActiveFilters: _hasFilters,
            currentSort: _currentSort,
            onSortChanged: (sort) {
              setState(() {
                _currentSort = sort;
                _refreshBusList();
              });
            },
          ),

          // ── Bus results list ──────────────────────────────────────────
          Expanded(
            child: _BusResultsList(
              key: _listKey,
              dbHelper: _dbHelper,
              busListFuture: _busListFuture,
              colorScheme: colorScheme,
              onRefresh: _refreshBusList,
            ),
          ),
        ],
      ),

      // ── Drawer ──────────────────────────────────────────────────────────
      drawer: _AppDrawer(colorScheme: colorScheme),

      // ── FAB ──────────────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_bus_fab'),
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AddBusScreen()),
          );
          if (added == true && mounted) {
            _refreshBusList();
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Bus',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 3,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search bar widget
// ---------------------------------------------------------------------------

class _BusSearchBar extends StatefulWidget {
  const _BusSearchBar({
    required this.controller,
    required this.focusNode,
    required this.colorScheme,
    required this.dbHelper,
    required this.onRefresh,
    required this.onFilterPressed,
    required this.hasActiveFilters,
    required this.currentSort,
    required this.onSortChanged,
  });

  final SearchController controller;
  final FocusNode focusNode;
  final ColorScheme colorScheme;
  final DatabaseHelper dbHelper;
  final VoidCallback onRefresh;
  final VoidCallback onFilterPressed;
  final bool hasActiveFilters;
  final String currentSort;
  final ValueChanged<String> onSortChanged;

  @override
  State<_BusSearchBar> createState() => _BusSearchBarState();
}

class _BusSearchBarState extends State<_BusSearchBar> {
  /// Queries the DB based on the search text across multiple columns.
  Future<List<Map<String, dynamic>>> _searchBuses(String query) async {
    final db = await widget.dbHelper.database;
    return db.query(
      DatabaseHelper.tablesBuses,
      where:
          '${DatabaseHelper.columnBusName} LIKE ? OR ${DatabaseHelper.columnDestination} LIKE ? OR ${DatabaseHelper.columnDepartureTime} LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: '${DatabaseHelper.columnBusName} ASC',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SearchAnchor(
        searchController: widget.controller,
        suggestionsBuilder: (context, controller) async {
          final query = controller.text.trim();

          if (query.isEmpty) return [];

          final results = await _searchBuses(query);

          if (results.isEmpty) {
            return [
              ListTile(
                leading: Icon(
                  Icons.search_off_rounded,
                  color: widget.colorScheme.outline,
                ),
                title: Text(
                  'No buses found for "$query"',
                  style: TextStyle(color: widget.colorScheme.onSurfaceVariant),
                ),
              ),
            ];
          }

          return results.map((bus) {
            final name = bus[DatabaseHelper.columnBusName] as String;
            final from = bus[DatabaseHelper.columnStartLocation] as String;
            final to = bus[DatabaseHelper.columnDestination] as String;
            final dbTime = bus[DatabaseHelper.columnDepartureTime] as String;
            String displayTime = dbTime;
            try {
              final parts = dbTime.split(':');
              if (parts.length == 2) {
                int h = int.parse(parts[0]);
                final m = parts[1];
                final period = h >= 12 ? 'PM' : 'AM';
                if (h > 12) h -= 12;
                if (h == 0) h = 12;
                displayTime = '$h:$m $period';
              }
            } catch (_) {}

            return ListTile(
              key: ValueKey(bus[DatabaseHelper.columnId]),
              leading: CircleAvatar(
                backgroundColor: widget.colorScheme.primaryContainer,
                child: Icon(
                  Icons.directions_bus_rounded,
                  color: widget.colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '$from → $to',
                style: TextStyle(
                  color: widget.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: Chip(
                label: Text(
                  displayTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                backgroundColor: widget.colorScheme.secondaryContainer,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide.none,
              ),
              onTap: () {
                controller.closeView('');
                FocusManager.instance.primaryFocus?.unfocus();
                showBusDetailsSheet(
                  context: context,
                  bus: bus,
                  colorScheme: widget.colorScheme,
                  dbHelper: widget.dbHelper,
                  onRefresh: widget.onRefresh,
                );
              },
            );
          }).toList();
        },
        builder: (context, controller) {
          return SearchBar(
            key: const Key('bus_search_bar'),
            controller: controller,
            focusNode: widget.focusNode,
            hintText: 'Search buses, routes, destinations…',
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            leading: Icon(
              Icons.search_rounded,
              color: widget.colorScheme.onSurfaceVariant,
            ),
            trailing: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort_rounded),
                tooltip: 'Sort by',
                initialValue: widget.currentSort,
                onSelected: widget.onSortChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Time', child: Text('Time')),
                  PopupMenuItem(value: 'A-Z', child: Text('A-Z')),
                  PopupMenuItem(value: 'Z-A', child: Text('Z-A')),
                  PopupMenuItem(value: 'Date Added', child: Text('Date Added')),
                ],
              ),
              IconButton(
                key: const Key('filter_button'),
                tooltip: 'Advanced Filters',
                icon: Badge(
                  isLabelVisible: widget.hasActiveFilters,
                  smallSize: 8,
                  child: Icon(
                    Icons.filter_list_rounded,
                    color: widget.hasActiveFilters
                        ? widget.colorScheme.primary
                        : widget.colorScheme.onSurfaceVariant,
                  ),
                ),
                onPressed: widget.onFilterPressed,
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                ),
            ],
            elevation: const WidgetStatePropertyAll(1.5),
            onTap: controller.openView,
            onChanged: (_) => controller.openView(),
          );
        },
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Bus results list — live FutureBuilder
// ---------------------------------------------------------------------------

class _BusResultsList extends StatelessWidget {
  const _BusResultsList({
    super.key,
    required this.dbHelper,
    required this.busListFuture,
    required this.colorScheme,
    required this.onRefresh,
  });

  final DatabaseHelper dbHelper;
  final Future<List<Map<String, dynamic>>> busListFuture;
  final ColorScheme colorScheme;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: busListFuture,
      builder: (context, snapshot) {
        // ── Loading ──────────────────────────────────────────────────────
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: colorScheme.primary,
            ),
          );
        }

        // ── Error ────────────────────────────────────────────────────────
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 48, color: colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'Failed to load buses',
                  style: TextStyle(color: colorScheme.error),
                ),
              ],
            ),
          );
        }

        final buses = snapshot.data ?? [];

        // ── Empty state ──────────────────────────────────────────────────
        if (buses.isEmpty) {
          return _EmptyState(colorScheme: colorScheme);
        }

        // ── List ─────────────────────────────────────────────────────────
        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          color: colorScheme.primary,
          child: ListView.separated(
            key: const Key('bus_results_list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: buses.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _BusTile(
                bus: buses[index],
                colorScheme: colorScheme,
                dbHelper: dbHelper,
                onRefresh: onRefresh,
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bus tile card
// ---------------------------------------------------------------------------

class _BusTile extends StatefulWidget {
  const _BusTile({
    required this.bus,
    required this.colorScheme,
    required this.dbHelper,
    required this.onRefresh,
  });

  final Map<String, dynamic> bus;
  final ColorScheme colorScheme;
  final DatabaseHelper dbHelper;
  final VoidCallback onRefresh;

  @override
  State<_BusTile> createState() => _BusTileState();
}

class _BusTileState extends State<_BusTile> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite =
        (widget.bus[DatabaseHelper.columnIsFavorite] as int? ?? 0) == 1;
  }

  Future<void> _toggleFavorite() async {
    final id = widget.bus[DatabaseHelper.columnId] as int;
    final wasFavorite = _isFavorite;
    // Optimistic UI — flip locally first for instant feedback.
    setState(() => _isFavorite = !_isFavorite);
    await widget.dbHelper.toggleFavorite(id, currentlyFavorite: wasFavorite);
    widget.onRefresh();
  }

  void _showBusDetails(BuildContext context) {
    showBusDetailsSheet(
      context: context,
      bus: widget.bus,
      colorScheme: widget.colorScheme,
      dbHelper: widget.dbHelper,
      onRefresh: widget.onRefresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bus = widget.bus;
    final colorScheme = widget.colorScheme;
    final name = bus[DatabaseHelper.columnBusName] as String;
    final from = bus[DatabaseHelper.columnStartLocation] as String;
    final to = bus[DatabaseHelper.columnDestination] as String;
    final dbTime = bus[DatabaseHelper.columnDepartureTime] as String;
    String time = dbTime;
    try {
      final parts = dbTime.split(':');
      if (parts.length == 2) {
        int h = int.parse(parts[0]);
        final m = parts[1];
        final period = h >= 12 ? 'PM' : 'AM';
        if (h > 12) h -= 12;
        if (h == 0) h = 12;
        time = '$h:$m $period';
      }
    } catch (_) {}
    final faresRaw = bus[DatabaseHelper.columnFares] as String? ?? '[]';

    int fareCount = 0;
    try {
      final decoded = jsonDecode(faresRaw) as List<dynamic>;
      fareCount = decoded.length;
    } catch (_) {}

    return Card(
      key: ValueKey(bus[DatabaseHelper.columnId]),
      elevation: _isFavorite ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: _isFavorite
            ? BorderSide(
                color: colorScheme.primary.withAlpha(100),
                width: 1.5,
              )
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showBusDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              // ── Bus icon avatar ──────────────────────────────────────────
              CircleAvatar(
                radius: 26,
                backgroundColor: _isFavorite
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHigh,
                child: Icon(
                  Icons.directions_bus_rounded,
                  color: _isFavorite
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),

              // ── Details ──────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            size: 13, color: colorScheme.primary),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            '$from → $to',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.access_time_rounded,
                          label: time,
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 6),
                        if (fareCount > 0)
                          _InfoChip(
                            icon: Icons.confirmation_number_rounded,
                            label:
                                '$fareCount ${fareCount == 1 ? 'fare' : 'fares'}',
                            colorScheme: colorScheme,
                            isSecondary: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Favorite toggle ──────────────────────────────────────────
              IconButton(
                key: ValueKey('fav_${bus[DatabaseHelper.columnId]}'),
                tooltip: _isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                onPressed: _toggleFavorite,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: child,
                  ),
                  child: Icon(
                    _isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    key: ValueKey(_isFavorite),
                    color: _isFavorite
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.colorScheme,
    this.isSecondary = false,
  });

  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    final bg = isSecondary
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;
    final fg = isSecondary
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_bus_outlined,
            size: 80,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No buses added yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the + Add Bus button to get started.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 80), // clear the FAB
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App Drawer
// ---------------------------------------------------------------------------

class _AppDrawer extends StatefulWidget {
  const _AppDrawer({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  int _selectedIndex = 0;
  late Future<String> _appVersionFuture;

  @override
  void initState() {
    super.initState();
    _appVersionFuture = getAppVersion();
  }

  Future<String> getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  void _showAboutDialog(BuildContext context) {
    final colorScheme = widget.colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/logo.png',
                width: 88,
                height: 88,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),
            // App name
            Text(
              'Bus Time Saver',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            // Version chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: FutureBuilder<String>(
                future: _appVersionFuture,
                builder: (context, snapshot) {
                  return Text(
                    snapshot.hasData ? 'Version ${snapshot.data}' : 'Version...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  );
                }
              ),
            ),
            const SizedBox(height: 16),
            // Tagline
            Text(
              'Your routes. Your time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            // Developer credit
            Text(
              'Developed by Fire Gaming',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            // GitHub Link
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final Uri url = Uri.parse('https://github.com/abyjays');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.code_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'GitHub Repository',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;

    return NavigationDrawer(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() => _selectedIndex = index);

        if (index == 0) {
          // Home – just close the drawer
          Navigator.pop(context);
        } else if (index == 1) {
          // Settings
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        } else if (index == 2) {
          // About – reset selection then show dialog
          setState(() => _selectedIndex = 0);
          Navigator.pop(context);
          _showAboutDialog(context);
        }
      },
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/logo.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Bus Time Saver',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              FutureBuilder<String>(
                future: _appVersionFuture,
                builder: (context, snapshot) {
                  return Text(
                    snapshot.hasData ? 'Version ${snapshot.data}' : 'Version...',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  );
                }
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Divider(),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: Text('Home'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: Text('Settings'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.info_outline_rounded),
          selectedIcon: Icon(Icons.info_rounded),
          label: Text('About'),
        ),
        // Removed illegal Spacer() here
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: Text(
              'Developed by Fire Gaming',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.outline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void showBusDetailsSheet({
  required BuildContext context, 
  required Map<String, dynamic> bus, 
  required ColorScheme colorScheme, 
  required DatabaseHelper dbHelper, 
  required VoidCallback onRefresh,
}) { 
  showModalBottomSheet(
    context: context, 
    isScrollControlled: true, 
    useSafeArea: true, 
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ), 
    builder: (sheetContext) { 
      String formatTimeStr(String? dbTimeStr) {
        if (dbTimeStr == null || dbTimeStr.isEmpty) return '';
        try {
          final parts = dbTimeStr.split(':');
          if (parts.length == 2) {
            int h = int.parse(parts[0]);
            final m = parts[1];
            final period = h >= 12 ? 'PM' : 'AM';
            if (h > 12) h -= 12;
            if (h == 0) h = 12;
            return '$h:$m $period';
          }
        } catch (_) {}
        return dbTimeStr;
      }

      final name = bus[DatabaseHelper.columnBusName] as String; 
      final from = bus[DatabaseHelper.columnStartLocation] as String; 
      final to = bus[DatabaseHelper.columnDestination] as String; 
      
      final time = formatTimeStr(bus[DatabaseHelper.columnDepartureTime] as String?); 
      final reachingTime = formatTimeStr(bus[DatabaseHelper.columnReachingTime] as String?);

      String timeDisplay = time;
      if (reachingTime.isNotEmpty) {
        timeDisplay = '$time  ➔  Reaching: $reachingTime';
      } 
      final faresRaw = bus[DatabaseHelper.columnFares] as String? ?? '[]';
      List<Map<String, dynamic>> fares = [];
      try {
        final decoded = jsonDecode(faresRaw) as List<dynamic>;
        fares = decoded.map((e) => e as Map<String, dynamic>).toList();
      } catch (_) {}
      
      return Padding(
        padding: const EdgeInsets.all(24), 
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          crossAxisAlignment: CrossAxisAlignment.stretch, 
          children: [ 
            Center(
              child: Container(
                width: 40, 
                height: 4, 
                margin: const EdgeInsets.only(bottom: 24), 
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withAlpha(128), 
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ), 
            Text(
              name, 
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.w800, 
                color: colorScheme.onSurface,
              ), 
              textAlign: TextAlign.center,
            ), 
            const SizedBox(height: 8), 
            Text(
              '$from → $to  •  $timeDisplay', 
              style: TextStyle(
                fontSize: 15, 
                color: colorScheme.onSurfaceVariant,
              ), 
              textAlign: TextAlign.center,
            ), 
            if (fares.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: fares.map((f) => Chip(
                  label: Text('${f['type']}: ₹${f['fare']}'),
                  backgroundColor: colorScheme.secondaryContainer,
                  labelStyle: TextStyle(
                    color: colorScheme.onSecondaryContainer, 
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide.none,
                )).toList(),
              ),
            ],
            const SizedBox(height: 32), 
            Row(
              children: [ 
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async { 
                      final id = bus[DatabaseHelper.columnId] as int; 
                      await dbHelper.deleteBus(id); 
                      if (sheetContext.mounted) { 
                        Navigator.pop(sheetContext); 
                        onRefresh(); 
                      } 
                    }, 
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error, 
                      side: BorderSide(color: colorScheme.error.withAlpha(128)), 
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ), 
                    icon: const Icon(Icons.delete_outline_rounded), 
                    label: const Text('Delete'),
                  ),
                ), 
                const SizedBox(width: 16), 
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async { 
                      Navigator.pop(sheetContext); 
                      if (!context.mounted) return; 
                      final changed = await Navigator.push<bool>(
                        context, 
                        MaterialPageRoute(
                          builder: (_) => AddBusScreen(busData: bus),
                        ),
                      ); 
                      if (changed == true) onRefresh(); 
                    }, 
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ), 
                    icon: const Icon(Icons.edit_rounded), 
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  ); 
}
