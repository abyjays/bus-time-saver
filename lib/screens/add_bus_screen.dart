import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../services/connectivity_service.dart';
import '../widgets/custom_fields.dart';

// ---------------------------------------------------------------------------
// Fare type options
// ---------------------------------------------------------------------------
const List<String> _fareTypes = [
  'Full',
  'ST',
  'Half',
  'Senior',
  'Monthly Pass',
];

// ---------------------------------------------------------------------------
// Indian states
// ---------------------------------------------------------------------------
const List<String> indianStates = [
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
  'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
  'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram',
  'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu',
  'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
  'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu',
  'Lakshadweep', 'Delhi', 'Puducherry'
];


class AddBusScreen extends StatefulWidget {
  /// Pass [busData] to open the screen in edit mode.
  const AddBusScreen({super.key, this.busData});

  /// When non-null, the screen pre-fills fields and calls [DatabaseHelper.updateBus].
  final Map<String, dynamic>? busData;

  @override
  State<AddBusScreen> createState() => _AddBusScreenState();
}

class _AddBusScreenState extends State<AddBusScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── Form controllers ──────────────────────────────────────────────────────
  final _busNameController = TextEditingController();
  final _startLocationController = TextEditingController();
  final _destinationController = TextEditingController();
  final _stateController = TextEditingController();
  final _priceController = TextEditingController();

  // ── Autocomplete data (offline / DB-backed) ───────────────────────────────
  List<String> _busNames = [];
  List<String> _startLocations = [];
  List<String> _destinations = [];

  // Focus nodes
  final _busNameFocus = FocusNode();
  final _startLocationFocus = FocusNode();
  final _destinationFocus = FocusNode();
  final _stateFocus = FocusNode();

  // ── State fields ──────────────────────────────────────────────────────────
  TimeOfDay? _selectedTime;
  TimeOfDay? _selectedReachingTime;
  String _selectedFareType = _fareTypes.first;
  final List<Map<String, dynamic>> _fares = [];
  bool _isSaving = false;

  // ── Intermediate stops ─────────────────────────────────────────────────────
  /// Each entry: {'name': String, 'type': 'Bus Stop' | 'Bus Stand'}
  final List<Map<String, dynamic>> _stops = [];
  final List<TextEditingController> _stopControllers = [];
  final List<FocusNode> _stopFocusNodes = [];

  /// Real-time online/offline flag used by location autocomplete.
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySub;

  /// True when the screen was opened with existing [busData].
  bool get _isEditing => widget.busData != null;

  @override
  void initState() {
    super.initState();
    _prefillForEdit();
    _loadAutocompleteData();
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    final online = await ConnectivityService().isOnline();
    if (mounted) setState(() => _isOnline = online);
    _connectivitySub = ConnectivityService().onlineStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _loadAutocompleteData() async {
    final busNames =
        await _dbHelper.getDistinctValues(DatabaseHelper.columnBusName);
    final startLocations =
        await _dbHelper.getDistinctValues(DatabaseHelper.columnStartLocation);
    final destinations =
        await _dbHelper.getDistinctValues(DatabaseHelper.columnDestination);
    if (mounted) {
      setState(() {
        _busNames = busNames;
        _startLocations = startLocations;
        _destinations = destinations;
      });
    }
  }

  /// Pre-fills all form fields when in edit mode.
  void _prefillForEdit() {
    final data = widget.busData;
    if (data == null) return;

    _busNameController.text =
        (data[DatabaseHelper.columnBusName] as String?) ?? '';
    _startLocationController.text =
        (data[DatabaseHelper.columnStartLocation] as String?) ?? '';
    _destinationController.text =
        (data[DatabaseHelper.columnDestination] as String?) ?? '';
    _stateController.text =
        (data[DatabaseHelper.columnState] as String?) ?? '';

    // Parse stored time string back to TimeOfDay
    final timeStr =
        (data[DatabaseHelper.columnDepartureTime] as String?) ?? '';
    _selectedTime = _parseTimeString(timeStr);

    final reachingStr =
        (data[DatabaseHelper.columnReachingTime] as String?) ?? '';
    _selectedReachingTime = _parseTimeString(reachingStr);

    // Parse stored fares JSON
    final faresRaw = (data[DatabaseHelper.columnFares] as String?) ?? '[]';
    try {
      final decoded = jsonDecode(faresRaw);
      if (decoded is List) {
        // Safely extract maps from the list
        for (var item in decoded) {
          if (item is Map) {
            _fares.add(Map<String, dynamic>.from(item));
          }
        }
      }
    } catch (_) {
      // Fallback to empty list on error
    }

    // Parse stored stops JSON
    final stopsRaw = (data[DatabaseHelper.columnStops] as String?) ?? '[]';
    try {
      final decoded = jsonDecode(stopsRaw);
      if (decoded is List) {
        for (var item in decoded) {
          if (item is Map) {
            final stop = Map<String, dynamic>.from(item);
            _stops.add(stop);
            _stopControllers.add(
              TextEditingController(text: stop['name'] as String? ?? ''),
            );
            _stopFocusNodes.add(FocusNode());
          }
        }
      }
    } catch (_) {
      // Fallback to empty list on error
    }
  }

  /// Parses a time string like "14:30" (24-hour format) back into a [TimeOfDay].
  TimeOfDay? _parseTimeString(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length != 2) return null;
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _busNameController.dispose();
    _startLocationController.dispose();
    _destinationController.dispose();
    _stateController.dispose();
    _priceController.dispose();
    _busNameFocus.dispose();
    _startLocationFocus.dispose();
    _destinationFocus.dispose();
    _stateFocus.dispose();
    for (final c in _stopControllers) {
      c.dispose();
    }
    for (final fn in _stopFocusNodes) {
      fn.dispose();
    }
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTime(TimeOfDay? time, String defaultText) {
    if (time == null) return defaultText;
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String get _formattedTime => _formatTime(_selectedTime, 'Select Departure Time');
  String get _formattedReachingTime => _formatTime(_selectedReachingTime, 'Select Reaching Time (Optional)');

  String _dbFormatTime(TimeOfDay? time) {
    if (time == null) return '';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get _dbFormattedTime => _dbFormatTime(_selectedTime);
  String get _dbFormattedReachingTime => _dbFormatTime(_selectedReachingTime);

  Future<void> _pickTime({bool isReachingTime = false}) async {
    final initial = isReachingTime ? _selectedReachingTime : _selectedTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isReachingTime) {
          _selectedReachingTime = picked;
        } else {
          _selectedTime = picked;
        }
      });
    }
  }

  void _addFare() {
    final priceText = _priceController.text.trim();
    if (priceText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a price before adding.')),
      );
      return;
    }
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid positive price.')),
      );
      return;
    }
    // Prevent duplicate fare types
    if (_fares.any((f) => f['type'] == _selectedFareType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_selectedFareType fare already added.')),
      );
      return;
    }
    setState(() {
      _fares.add({'type': _selectedFareType, 'fare': price});
      _priceController.clear();
    });
  }

  void _removeFare(int index) {
    setState(() => _fares.removeAt(index));
  }

  // ── Stop helpers ───────────────────────────────────────────────────────────

  void _showAddStopDialog() {
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Intermediate Stop'),
        content: const Text('Choose the type of stop to add:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'Bus Stop'),
            child: const Text('Bus Stop'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'Bus Stand'),
            child: const Text('Bus Stand'),
          ),
        ],
      ),
    ).then((type) {
      if (type != null) {
        setState(() {
          _stops.add({'name': '', 'type': type});
          _stopControllers.add(TextEditingController());
          _stopFocusNodes.add(FocusNode());
        });
      }
    });
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
      _stopControllers[index].dispose();
      _stopControllers.removeAt(index);
      _stopFocusNodes[index].dispose();
      _stopFocusNodes.removeAt(index);
    });
  }

  Future<void> _saveBus() async {
    // Sanitize text inputs: trim ends and collapse multiple internal spaces
    _busNameController.text =
        _busNameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    _startLocationController.text =
        _startLocationController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    _destinationController.text =
        _destinationController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    _stateController.text =
        _stateController.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (!_formKey.currentState!.validate()) return;

    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a departure time.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Sync stop names from controllers back into _stops list
      for (int i = 0; i < _stops.length; i++) {
        _stops[i] = {
          'name': _stopControllers[i].text.trim().replaceAll(RegExp(r'\s+'), ' '),
          'type': _stops[i]['type'],
        };
      }

      final Map<String, dynamic> record = {
        DatabaseHelper.columnBusName: _busNameController.text,
        DatabaseHelper.columnStartLocation: _startLocationController.text,
        DatabaseHelper.columnDestination: _destinationController.text,
        DatabaseHelper.columnDepartureTime: _dbFormattedTime,
        DatabaseHelper.columnReachingTime: _dbFormattedReachingTime,
        DatabaseHelper.columnFares: jsonEncode(_fares),
        DatabaseHelper.columnState: _stateController.text,
        DatabaseHelper.columnStops: jsonEncode(_stops),
      };

      if (_isEditing) {
        // Preserve the original id (int) for the WHERE clause
        record[DatabaseHelper.columnId] =
            widget.busData![DatabaseHelper.columnId] as int;
        await _dbHelper.updateBus(record);
      } else {
        await _dbHelper.insertBus(record);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // signal caller that a change was made
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save bus: $e')));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        title: Text(
          _isEditing ? 'Edit Bus' : 'Add New Bus',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
        actions: [
          // Subtle online/offline indicator so the user knows live
          // autocomplete is active.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _isOnline
                  ? Tooltip(
                      key: const ValueKey('online'),
                      message: 'Online – live location suggestions active',
                      child: Icon(Icons.wifi_rounded,
                          size: 18, color: Colors.green[600]),
                    )
                  : Tooltip(
                      key: const ValueKey('offline'),
                      message: 'Offline – using saved suggestions',
                      child: Icon(Icons.wifi_off_rounded,
                          size: 18, color: colorScheme.outline),
                    ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        // Tapping anywhere outside a text field drops focus, which causes
        // RawAutocomplete to automatically close its overlay (it listens to
        // the field's FocusNode). HitTestBehavior.opaque ensures the gesture
        // is received even over transparent/empty areas of the scroll view.
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
            // ── Section: Bus Details ──────────────────────────────────────────
            _SectionHeader(
              icon: Icons.info_outline_rounded,
              label: 'Bus Details',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 16),

            // Bus name (DB-backed autocomplete, same as before)
            StyledAutocompleteField(
              controller: _busNameController,
              focusNode: _busNameFocus,
              suggestions: _busNames,
              label: 'Bus Name',
              hint: 'Bus name',
              icon: Icons.directions_bus_rounded,
              colorScheme: colorScheme,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Bus name is required'
                  : null,
            ),
            const SizedBox(height: 14),

            // State (dropdown, optional — used to localise location API)
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: indianStates.contains(_stateController.text)
                  ? _stateController.text
                  : null,
              decoration: InputDecoration(
                labelText: 'State',
                hintText: 'Select State',
                prefixIcon: Icon(Icons.map_outlined, color: colorScheme.primary),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(100),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
              items: indianStates.map((state) {
                return DropdownMenuItem(
                  value: state,
                  child: Text(state),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _stateController.text = val;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // Start location — live autocomplete when online, DB fallback offline
            LiveLocationField(
              controller: _startLocationController,
              focusNode: _startLocationFocus,
              label: 'Start Location',
              hint: 'Start Location',
              icon: Icons.location_on_rounded,
              colorScheme: colorScheme,
              isOnline: _isOnline,
              stateHint: _stateController.text,
              offlineSuggestions: _startLocations,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Start location is required'
                  : null,
            ),
            const SizedBox(height: 16),

            // ── Intermediate Stops ────────────────────────────────────────
            _SectionHeader(
              icon: Icons.route_rounded,
              label: 'Intermediate Stops',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 8),

            // "Add Stop" button row
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _showAddStopDialog,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add Stop or Stand',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _stops.isEmpty
                      ? 'No intermediate stops added'
                      : '${_stops.length} stop${_stops.length == 1 ? '' : 's'} added',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // Per-stop fields
            if (_stops.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...List.generate(_stops.length, (i) {
                final stopType = _stops[i]['type'] as String;
                final isStand = stopType == 'Bus Stand';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: LiveLocationField(
                          controller: _stopControllers[i],
                          focusNode: _stopFocusNodes[i],
                          label: stopType,
                          hint: 'Enter $stopType name',
                          icon: isStand
                              ? Icons.transfer_within_a_station_rounded
                              : Icons.pin_drop_rounded,
                          iconColor: isStand
                              ? colorScheme.tertiary
                              : colorScheme.secondary,
                          focusedBorderColor: isStand
                              ? colorScheme.tertiary
                              : colorScheme.secondary,
                          enabledBorderColor: isStand
                              ? colorScheme.tertiary.withAlpha(120)
                              : colorScheme.secondary.withAlpha(120),
                          colorScheme: colorScheme,
                          isOnline: _isOnline,
                          stateHint: _stateController.text,
                          offlineSuggestions: _destinations,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? '$stopType name is required'
                              : null,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.remove_circle_outline_rounded,
                          color: colorScheme.error,
                          size: 20,
                        ),
                        tooltip: 'Remove stop',
                        onPressed: () => _removeStop(i),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 8),

            // Destination — live autocomplete when online, DB fallback offline
            LiveLocationField(
              controller: _destinationController,
              focusNode: _destinationFocus,
              label: 'Destination',
              hint: 'Destination',
              icon: Icons.flag_rounded,
              colorScheme: colorScheme,
              isOnline: _isOnline,
              stateHint: _stateController.text,
              offlineSuggestions: _destinations,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Destination is required'
                  : null,
            ),
            const SizedBox(height: 14),

            // ── Schedule section ──────────────────────────────────────────
            _SectionHeader(
              icon: Icons.schedule_rounded,
              label: 'Schedule',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),

            InkWell(
              onTap: () => _pickTime(isReachingTime: false),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedTime != null
                        ? colorScheme.primary
                        : colorScheme.outline.withAlpha(100),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      color: _selectedTime != null
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _formattedTime,
                        style: textTheme.bodyLarge?.copyWith(
                          color: _selectedTime != null
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                          fontWeight: _selectedTime != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant.withAlpha(150),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            InkWell(
              onTap: () => _pickTime(isReachingTime: true),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedReachingTime != null
                        ? colorScheme.primary
                        : colorScheme.outline.withAlpha(100),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.flag_rounded,
                      color: _selectedReachingTime != null
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _formattedReachingTime,
                        style: textTheme.bodyLarge?.copyWith(
                          color: _selectedReachingTime != null
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                          fontWeight: _selectedReachingTime != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant.withAlpha(150),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Section: Fares ────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.payments_rounded,
              label: 'Fares',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),

            // Fare input row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fare type dropdown
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.outline.withAlpha(100),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedFareType,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(12),
                        items: _fareTypes
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedFareType = v);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Price input
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Price (₹)',
                      prefixText: '₹ ',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withAlpha(100),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Add fare button
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _addFare,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Icon(Icons.add_rounded, size: 24),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Fares list
            if (_fares.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No fares added yet. Use the row above to add fare tiers.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...List.generate(_fares.length, (i) {
                final fare = _fares[i];
                return _FareTile(
                  type: fare['type'] as String,
                  price: fare['fare'] as double,
                  colorScheme: colorScheme,
                  onDelete: () => _removeFare(i),
                );
              }),
            ],
          ),
        ),
      ),

      // ── Save FAB ─────────────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('save_bus_fab'),
        onPressed: _isSaving ? null : _saveBus,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.check_rounded),
        label: Text(
          _isEditing ? 'Update Bus' : 'Save Bus',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 3,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable: Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.colorScheme,
  });

  final IconData icon;
  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(color: colorScheme.outlineVariant, thickness: 1),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable: Fare tile in the list
// ---------------------------------------------------------------------------

class _FareTile extends StatelessWidget {
  const _FareTile({
    required this.type,
    required this.price,
    required this.colorScheme,
    required this.onDelete,
  });

  final String type;
  final double price;
  final ColorScheme colorScheme;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withAlpha(153),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.secondary.withAlpha(77)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.confirmation_number_rounded,
              size: 18,
              color: colorScheme.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                type,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            Text(
              '₹ ${price % 1 == 0 ? price.toInt() : price.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                color: colorScheme.error,
                size: 20,
              ),
              tooltip: 'Remove',
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

