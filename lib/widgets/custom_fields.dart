import 'dart:async';
import 'package:flutter/material.dart';
import '../services/location_service.dart';

class LiveLocationField extends StatefulWidget {
  const LiveLocationField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    required this.colorScheme,
    required this.isOnline,
    required this.stateHint,
    required this.offlineSuggestions,
    this.validator,
    this.iconColor,
    this.focusedBorderColor,
    this.enabledBorderColor,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final ColorScheme colorScheme;
  final bool isOnline;
  final String stateHint;
  final List<String> offlineSuggestions;
  final String? Function(String?)? validator;
  final Color? iconColor;
  final Color? focusedBorderColor;
  final Color? enabledBorderColor;

  @override
  State<LiveLocationField> createState() => _LiveLocationFieldState();
}

class _LiveLocationFieldState extends State<LiveLocationField> {
  Timer? _debounce;
  bool _loading = false;

  // The live suggestions are kept here and are updated asynchronously.
  // We notify the RawAutocomplete to rebuild by calling
  // _optionsController.add(), which the optionsBuilder listens to.
  final _optionsController = StreamController<List<String>>.broadcast();
  List<String> _lastOptions = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _optionsController.close();
    super.dispose();
  }

  Future<Iterable<String>> _fetchOptions(TextEditingValue textEditingValue) async {
    final query = textEditingValue.text.trim();

    if (query.isEmpty) {
      return const [];
    }

    // Offline or query too short — use local DB-backed suggestions.
    // Offline suggestions are plain place names (no state metadata), so they
    // are filtered only by the query text. State-strict filtering applies only
    // to live API results (handled inside LocationService.fetchSuggestions).
    if (!widget.isOnline || query.length < 2) {
      final offline = widget.offlineSuggestions
          .where((o) => o.toLowerCase().contains(query.toLowerCase()))
          .toList();
      debugPrint('Fetched suggestions count (offline): ${offline.length}');
      return offline;
    }

    // Show loading indicator.
    if (mounted) setState(() => _loading = true);

    try {
      // LocationService.fetchSuggestions strictly filters by [widget.stateHint]
      // when it is non-empty, so live results are guaranteed to be within the
      // selected state only.
      final results = await LocationService.fetchSuggestions(
        query,
        state: widget.stateHint,
      );
      debugPrint('Fetched suggestions count (live, state: "${widget.stateHint}"): ${results.length}');

      // Merge live (state-filtered) results with offline DB matches.
      // Offline suggestions are the user\'s own saved data and are always shown.
      final offlineMatches = widget.offlineSuggestions
          .where((o) => o.toLowerCase().contains(query.toLowerCase()))
          .toList();
      final merged = {...results, ...offlineMatches}.toList();

      return merged;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _buildDecoration({bool showLoader = false}) {
    final effectiveIconColor = widget.iconColor ?? widget.colorScheme.primary;
    final effectiveFocusedBorderColor = widget.focusedBorderColor ?? widget.colorScheme.primary;
    final effectiveEnabledBorderColor = widget.enabledBorderColor ?? widget.colorScheme.outline.withAlpha(100);

    return InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      prefixIcon: Icon(widget.icon, color: effectiveIconColor),
      suffixIcon: showLoader
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: effectiveIconColor,
                ),
              ),
            )
          : null,
      filled: true,
      fillColor: widget.colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: effectiveEnabledBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: effectiveFocusedBorderColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: widget.colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: widget.colorScheme.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: widget.focusNode,
      // This async optionsBuilder is the correct pattern for live fetching.
      // RawAutocomplete calls it every time the text changes and rebuilds the
      // overlay when the future completes.
      optionsBuilder: (TextEditingValue textEditingValue) async {
        final options = await _fetchOptions(textEditingValue);
        _lastOptions = options.toList();
        return _lastOptions;
      },
      onSelected: (String selection) {
        widget.controller.text = selection;
        debugPrint('Selected: $selection');
      },
      fieldViewBuilder: (BuildContext context,
          TextEditingController textEditingController,
          FocusNode focusNode,
          VoidCallback onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          validator: widget.validator,
          textCapitalization: TextCapitalization.words,
          decoration: _buildDecoration(showLoader: _loading),
        );
      },
      optionsViewBuilder: (BuildContext context,
          AutocompleteOnSelected<String> onSelected,
          Iterable<String> options) {
        if (options.isEmpty) return const SizedBox.shrink();

        debugPrint('optionsViewBuilder rendering ${options.length} options');

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SizedBox(
                width: MediaQuery.of(context).size.width - 32,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 44),
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      final bool isLive = !widget.offlineSuggestions.contains(option);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isLive
                              ? Icons.location_on_outlined
                              : Icons.history_rounded,
                          size: 18,
                          color: widget.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          option,
                          style: TextStyle(
                            color: widget.colorScheme.onSurface,
                            fontSize: 14,
                          ),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class StyledAutocompleteField extends StatelessWidget {
  const StyledAutocompleteField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    required this.colorScheme,
    this.validator,
    required this.suggestions,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final ColorScheme colorScheme;
  final String? Function(String?)? validator;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        final results = suggestions.where((String option) {
          return option
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
        debugPrint('Fetched suggestions count (StyledAutocomplete): ${results.length}');
        return results;
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder: (BuildContext context,
          TextEditingController textEditingController,
          FocusNode focusNode,
          VoidCallback onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          validator: validator,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: colorScheme.primary),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colorScheme.outline.withAlpha(100)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colorScheme.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colorScheme.error, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        );
      },
      optionsViewBuilder: (BuildContext context,
          AutocompleteOnSelected<String> onSelected,
          Iterable<String> options) {
        if (options.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SizedBox(
                width: MediaQuery.of(context).size.width - 32,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 44),
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.history_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          option,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                          ),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
