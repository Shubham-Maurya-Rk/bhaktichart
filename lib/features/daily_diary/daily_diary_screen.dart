import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_utils.dart';
import '../../models/day_note_model.dart';
import '../../repositories/sadhana_repository.dart';

class DailyDiaryScreen extends StatefulWidget {
  const DailyDiaryScreen({super.key});

  @override
  State<DailyDiaryScreen> createState() => _DailyDiaryScreenState();
}

class _DailyDiaryScreenState extends State<DailyDiaryScreen> {
  // ============================================================
  // REPOSITORY
  // ============================================================

  final SadhanaRepository _repository = SadhanaRepository();

  // ============================================================
  // USER
  // ============================================================

  int? _userId;
  String _name = '';

  // ============================================================
  // DATE / PAGE
  // ============================================================

  DateTime _selectedDate = DateTime.now();

  static const int _initialPage = 10000;

  late final PageController _pageController;

  // Used to prevent an older async database request from
  // overwriting a newer selected date.
  int _dateLoadRequest = 0;

  // ============================================================
  // NOTE
  // ============================================================

  DayNoteModel? _dayNote;

  // ============================================================
  // TEXT CONTROLLER
  // ============================================================

  late final TextEditingController _noteController;

  // ============================================================
  // FOCUS
  // ============================================================

  final FocusNode _noteFocusNode = FocusNode();

  // ============================================================
  // LOADING
  // ============================================================

  bool _isLoading = true;

  bool _isChangingDate = false;

  bool _isSaving = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: _initialPage);

    _noteController = TextEditingController();

    // Rebuild the Save button whenever the user types.
    _noteController.addListener(_onNoteChanged);

    _loadInitialData();
  }

  // ============================================================
  // NOTE CHANGED
  // ============================================================

  void _onNoteChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _pageController.dispose();

    _noteController.removeListener(_onNoteChanged);
    _noteController.dispose();

    _noteFocusNode.dispose();

    super.dispose();
  }

  // ============================================================
  // DATE KEY
  // ============================================================

  String _dateKey(DateTime date) {
    return AppDateUtils.formatDate(DateTime(date.year, date.month, date.day));
  }

  // ============================================================
  // NORMALIZED DATE
  // ============================================================

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  // ============================================================
  // INITIAL DATA
  // ============================================================

  Future<void> _loadInitialData() async {
    try {
      final user = await _repository.getUser();

      if (user == null || user.id == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _userId = user.id;
        _name = user.name;
      });

      await _loadDayNote(_normalizeDate(DateTime.now()), showLoader: false);
    } catch (e, stackTrace) {
      debugPrint('Error loading Daily Diary: $e');
      debugPrint('$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // FUTURE DATE
  // ============================================================

  bool _isFutureDate(DateTime date) {
    final today = _normalizeDate(DateTime.now());

    final normalizedDate = _normalizeDate(date);

    return normalizedDate.isAfter(today);
  }

  // ============================================================
  // TODAY
  // ============================================================

  bool get _isToday {
    final today = _normalizeDate(DateTime.now());

    final selected = _normalizeDate(_selectedDate);

    return selected == today;
  }

  // ============================================================
  // LOAD DAY NOTE
  // ============================================================

  Future<void> _loadDayNote(DateTime date, {bool showLoader = true}) async {
    if (_userId == null) {
      return;
    }

    final normalizedDate = _normalizeDate(date);

    // Every new request gets a unique ID.
    // If another date is selected before this request finishes,
    // this request will no longer be allowed to update the UI.
    final requestId = ++_dateLoadRequest;

    if (showLoader && mounted) {
      setState(() {
        _isChangingDate = true;
      });
    }

    try {
      final dateKey = _dateKey(normalizedDate);

      final note = await _repository.getDayNote(_userId!, dateKey);

      if (!mounted) {
        return;
      }

      // Ignore stale database responses.
      if (requestId != _dateLoadRequest) {
        return;
      }

      final noteText = note?.note ?? '';

      setState(() {
        _selectedDate = normalizedDate;
        _dayNote = note;

        _noteController.value = TextEditingValue(
          text: noteText,
          selection: TextSelection.collapsed(offset: noteText.length),
        );
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading diary note: $e');
      debugPrint('$stackTrace');

      if (mounted && requestId == _dateLoadRequest) {
        _showMessage('Unable to load diary entry.', isError: true);
      }
    } finally {
      if (mounted && requestId == _dateLoadRequest) {
        setState(() {
          _isChangingDate = false;
        });
      }
    }
  }

  // ============================================================
  // CHANGE DAY
  // ============================================================

  Future<void> _changeDay(DateTime date) async {
    if (_isSaving) {
      return;
    }

    final normalizedDate = _normalizeDate(date);

    if (_isFutureDate(normalizedDate)) {
      return;
    }

    _noteFocusNode.unfocus();

    await _loadDayNote(normalizedDate);
  }

  // ============================================================
  // PAGE CHANGED
  // ============================================================

  Future<void> _onPageChanged(int page) async {
    final difference = page - _initialPage;

    final today = _normalizeDate(DateTime.now());

    final date = today.add(Duration(days: difference));

    // Never allow future dates.
    if (_isFutureDate(date)) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_initialPage);
      }

      await _loadDayNote(today, showLoader: false);

      return;
    }

    await _changeDay(date);
  }

  // ============================================================
  // DATE PICKER
  // ============================================================

  Future<void> _pickDate() async {
    if (_isChangingDate || _isSaving) {
      return;
    }

    final today = _normalizeDate(DateTime.now());

    final selected = await showDatePicker(
      context: context,

      initialDate: _isFutureDate(_selectedDate)
          ? today
          : _normalizeDate(_selectedDate),

      firstDate: DateTime(2020),

      lastDate: today,

      helpText: 'Select diary date',
    );

    if (selected == null) {
      return;
    }

    final selectedDate = _normalizeDate(selected);

    if (_isFutureDate(selectedDate)) {
      return;
    }

    final difference = selectedDate.difference(today).inDays;

    final targetPage = _initialPage + difference;

    if (!_pageController.hasClients) {
      await _changeDay(selectedDate);
      return;
    }

    _noteFocusNode.unfocus();

    await _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ============================================================
  // SAVE NOTE
  // ============================================================

  Future<void> _saveNote() async {
    if (_userId == null) {
      return;
    }

    if (_isFutureDate(_selectedDate)) {
      _showMessage('Future dates cannot be edited.', isError: true);
      return;
    }

    if (_isSaving) {
      return;
    }

    final text = _noteController.text.trim();

    if (text.isEmpty) {
      await _showEmptyNoteConfirmation();
      return;
    }

    _noteFocusNode.unfocus();

    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    }

    try {
      final now = DateTime.now().toIso8601String();

      final existingNote = _dayNote;

      final note = DayNoteModel(
        id: existingNote?.id,

        userId: _userId!,

        date: _dateKey(_selectedDate),

        // Preserve all existing day information.
        isStarred: existingNote?.isStarred ?? false,
        isSankirtan: existingNote?.isSankirtan ?? false,
        isEkadashi: existingNote?.isEkadashi ?? false,
        isFestival: existingNote?.isFestival ?? false,

        note: text,

        createdAt: existingNote?.createdAt ?? now,

        updatedAt: now,
      );

      await _repository.saveDayNote(note);

      // Reload the exact selected date.
      final savedNote = await _repository.getDayNote(
        _userId!,
        _dateKey(_selectedDate),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _dayNote = savedNote;

        final savedText = savedNote?.note ?? '';

        _noteController.value = TextEditingValue(
          text: savedText,
          selection: TextSelection.collapsed(offset: savedText.length),
        );
      });

      _showMessage('Diary entry saved.');
    } catch (e, stackTrace) {
      debugPrint('Error saving diary note: $e');
      debugPrint('$stackTrace');

      if (mounted) {
        _showMessage(
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // EMPTY NOTE CONFIRMATION
  // ============================================================

  Future<void> _showEmptyNoteConfirmation() async {
    final existingText = _dayNote?.note?.trim() ?? '';

    // There is no saved note.
    if (existingText.isEmpty) {
      _showMessage('Write something before saving.', isError: true);

      return;
    }

    final shouldClear = await showDialog<bool>(
      context: context,

      builder: (context) {
        final theme = Theme.of(context);

        return AlertDialog(
          title: const Text('Clear diary entry?'),

          content: const Text('The diary entry for this day will be removed.'),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },

              child: const Text('Cancel'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },

              child: Text(
                'Clear',
                style: TextStyle(color: theme.colorScheme.onPrimary),
              ),
            ),
          ],
        );
      },
    );

    if (shouldClear != true) {
      return;
    }

    await _clearNote();
  }

  // ============================================================
  // CLEAR NOTE
  // ============================================================

  Future<void> _clearNote() async {
    if (_userId == null || _dayNote == null) {
      _noteController.clear();
      return;
    }

    if (_isFutureDate(_selectedDate)) {
      return;
    }

    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final existing = _dayNote!;

      final note = DayNoteModel(
        id: existing.id,

        userId: existing.userId,

        date: existing.date,

        // Preserve day flags.
        isStarred: existing.isStarred,
        isSankirtan: existing.isSankirtan,
        isEkadashi: existing.isEkadashi,
        isFestival: existing.isFestival,

        note: null,

        createdAt: existing.createdAt,

        updatedAt: DateTime.now().toIso8601String(),
      );

      await _repository.saveDayNote(note);

      final refreshed = await _repository.getDayNote(
        _userId!,
        _dateKey(_selectedDate),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _dayNote = refreshed;

        _noteController.clear();
      });

      _showMessage('Diary entry cleared.');
    } catch (e, stackTrace) {
      debugPrint('Error clearing diary note: $e');
      debugPrint('$stackTrace');

      if (mounted) {
        _showMessage(
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    final theme = Theme.of(context);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),

          behavior: SnackBarBehavior.floating,

          backgroundColor: isError ? theme.colorScheme.error : null,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              'Daily Diary',

              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            if (_name.isNotEmpty)
              Text('Hare Krishna, $_name 🙏', style: theme.textTheme.bodySmall),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Select date',

            onPressed: _isChangingDate ? null : _pickDate,

            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),

      body: Column(
        children: [
          // ======================================================
          // DATE HEADER
          // ======================================================
          _buildDateHeader(context),

          // ======================================================
          // SWIPE AREA
          // ======================================================
          Expanded(
            child: PageView.builder(
              controller: _pageController,

              onPageChanged: _onPageChanged,

              itemCount: _initialPage + 1,

              itemBuilder: (context, index) {
                return RefreshIndicator(
                  onRefresh: () {
                    return _loadDayNote(_selectedDate, showLoader: false);
                  },

                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),

                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),

                    child: _buildDiaryContent(context),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DATE HEADER
  // ============================================================

  Widget _buildDateHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),

      child: Row(
        children: [
          // ------------------------------------------------------
          // PREVIOUS DAY
          // ------------------------------------------------------
          IconButton(
            tooltip: 'Previous day',

            onPressed: _isChangingDate
                ? null
                : () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 250),

                      curve: Curves.easeInOut,
                    );
                  },

            icon: const Icon(Icons.chevron_left),
          ),

          // ------------------------------------------------------
          // DATE
          // ------------------------------------------------------
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),

              onTap: _isChangingDate ? null : _pickDate,

              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),

                child: Column(
                  children: [
                    Text(
                      DateFormat('EEEE').format(_selectedDate),

                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,

                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      DateFormat('d MMMM yyyy').format(_selectedDate),

                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    if (_isToday)
                      Text(
                        'Today',

                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,

                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ------------------------------------------------------
          // NEXT DAY
          // ------------------------------------------------------
          IconButton(
            tooltip: _isToday ? 'Already at today' : 'Next day',

            onPressed: (_isChangingDate || _isToday)
                ? null
                : () {
                    final nextDate = _selectedDate.add(const Duration(days: 1));

                    if (_isFutureDate(nextDate)) {
                      return;
                    }

                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 250),

                      curve: Curves.easeInOut,
                    );
                  },

            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DIARY CONTENT
  // ============================================================

  Widget _buildDiaryContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        // ========================================================
        // DAY INFO
        // ========================================================

        // ========================================================
        // DIARY EDITOR
        // ========================================================
        _buildDiaryEditor(context),

        const SizedBox(height: 14),

        // ========================================================
        // SAVE BUTTON
        // ========================================================
        _buildSaveButton(context),
      ],
    );
  }

  // ============================================================
  // DIARY EDITOR
  // ============================================================

  Widget _buildDiaryEditor(BuildContext context) {
    final theme = Theme.of(context);

    final isFuture = _isFutureDate(_selectedDate);

    return Card(
      elevation: 0,

      color: theme.colorScheme.surfaceContainerHighest,

      child: Padding(
        padding: const EdgeInsets.all(14),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // ----------------------------------------------------
            // HEADER
            // ----------------------------------------------------
            Row(
              children: [
                Icon(
                  Icons.auto_stories_outlined,

                  color: theme.colorScheme.primary,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    _isToday ? 'Today\'s Diary' : 'Daily Diary',

                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                if (_dayNote?.note?.trim().isNotEmpty == true)
                  Icon(
                    Icons.check_circle_rounded,

                    size: 19,

                    color: theme.colorScheme.primary,
                  ),
              ],
            ),

            const SizedBox(height: 14),

            // ----------------------------------------------------
            // LARGE TEXT FIELD
            // ----------------------------------------------------
            TextField(
              controller: _noteController,

              focusNode: _noteFocusNode,

              enabled: !isFuture && !_isSaving,

              keyboardType: TextInputType.multiline,

              textCapitalization: TextCapitalization.sentences,

              minLines: 18,

              maxLines: 40,

              textInputAction: TextInputAction.newline,

              decoration: InputDecoration(
                hintText:
                    'Write about your day...\n\n'
                    'You can write a letter to yourself, '
                    'what you learned today, something you are grateful for, '
                    'your spiritual reflections, or anything you want to remember.',

                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,

                  height: 1.6,
                ),

                filled: true,

                fillColor: theme.colorScheme.surface,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),

                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),

                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),

                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),

                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),

                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,

                    width: 1.5,
                  ),
                ),

                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),

                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),

                contentPadding: const EdgeInsets.all(18),

                alignLabelWithHint: true,
              ),

              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),

            // ----------------------------------------------------
            // FUTURE MESSAGE
            // ----------------------------------------------------
            if (isFuture) ...[
              const SizedBox(height: 10),

              Row(
                children: [
                  Icon(
                    Icons.lock_clock_rounded,

                    size: 17,

                    color: theme.colorScheme.onSurfaceVariant,
                  ),

                  const SizedBox(width: 6),

                  Expanded(
                    child: Text(
                      'Future dates cannot be edited.',

                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SAVE BUTTON
  // ============================================================

  Widget _buildSaveButton(BuildContext context) {
    final isFuture = _isFutureDate(_selectedDate);

    final hasText = _noteController.text.trim().isNotEmpty;

    return SizedBox(
      width: double.infinity,

      child: FilledButton.icon(
        onPressed: (isFuture || _isSaving || !hasText) ? null : _saveNote,

        icon: _isSaving
            ? const SizedBox(
                height: 18,
                width: 18,

                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),

        label: Text(_isSaving ? 'Saving...' : 'Save Diary Entry'),

        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
