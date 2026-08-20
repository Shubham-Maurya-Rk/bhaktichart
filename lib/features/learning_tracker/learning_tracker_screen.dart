import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/learning_book.dart';
import '../../models/learning_shloka.dart';
import '../../repositories/learning_tracker_repository.dart';

enum ShlokaSortOption { dateNewest, dateOldest, referenceAsc, referenceDesc }

class LearningTrackerScreen extends StatefulWidget {
  final int userId;

  const LearningTrackerScreen({super.key, required this.userId});

  @override
  State<LearningTrackerScreen> createState() => _LearningTrackerScreenState();
}

class _LearningTrackerScreenState extends State<LearningTrackerScreen> {
  final LearningTrackerRepository _repository = LearningTrackerRepository();
  static const String _prefLastBookKey = 'last_opened_book_id_';

  // Constants
  static final LearningBook _allBooksOption = LearningBook(
    id: -1,
    userId: -1,
    name: 'All Books',
    levelCount: 1,
    createdAt: DateTime.now(),
  );

  List<LearningBook> _books = [];
  LearningBook? _selectedBook;
  List<LearningShloka> _shlokas = [];

  LearningStatus? _filter;
  String _searchQuery = '';
  ShlokaSortOption _sortBy = ShlokaSortOption.referenceAsc;

  // Hierarchical reference filtering state
  final List<String?> _selectedRefLevels = [null, null, null];

  bool _showTranslation = true;
  bool _loading = true;
  bool _isSearching = false;

  final TextEditingController _searchController = TextEditingController();

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // PREFERENCES
  // ============================================================

  Future<void> _saveLastBookId(int? bookId) async {
    final prefs = await SharedPreferences.getInstance();
    if (bookId != null) {
      await prefs.setInt('$_prefLastBookKey${widget.userId}', bookId);
    }
  }

  Future<int?> _getLastBookId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefLastBookKey${widget.userId}');
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _loadBooks() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      var books = await _repository.getBooks(widget.userId);

      // Create default "Others" book if it doesn't exist.
      if (!books.any((book) => book.name.trim().toLowerCase() == 'others')) {
        await _repository.addBook(
          LearningBook(
            userId: widget.userId,
            name: 'Others',
            levelCount: 1,
            createdAt: DateTime.now(),
          ),
        );

        books = await _repository.getBooks(widget.userId);
      }

      if (!mounted) return;

      final lastBookId = await _getLastBookId();

      setState(() {
        _books = books;

        if (lastBookId == -1) {
          _selectedBook = _allBooksOption;
        } else if (lastBookId != null) {
          final matching = books.where((b) => b.id == lastBookId);
          _selectedBook = matching.isNotEmpty
              ? matching.first
              : (books.isNotEmpty ? books.first : null);
        } else {
          _selectedBook = books.isNotEmpty ? books.first : null;
        }

        _loading = false;
      });

      await _loadShlokas();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showError(e.toString());
    }
  }

  Future<void> _loadShlokas() async {
    final book = _selectedBook;

    if (book == null) {
      if (!mounted) return;
      setState(() => _shlokas = []);
      return;
    }

    try {
      List<LearningShloka> shlokas = [];

      if (book.id == -1) {
        // Fetch shlokas across all books
        for (final b in _books) {
          final bShlokas = await _repository.getShlokas(
            userId: widget.userId,
            bookId: b.id!,
            status: _filter,
          );
          shlokas.addAll(bShlokas);
        }
      } else {
        shlokas = await _repository.getShlokas(
          userId: widget.userId,
          bookId: book.id!,
          status: _filter,
        );
      }

      if (!mounted) return;

      setState(() {
        _shlokas = shlokas;
      });
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _refresh() async {
    await _loadBooks();
  }

  // Helper to resolve book name for "All Books" view
  String _getBookName(int bookId) {
    return _books
        .firstWhere((b) => b.id == bookId, orElse: () => _allBooksOption)
        .name;
  }

  // Reset reference level breadcrumb choices
  void _resetRefLevels() {
    _selectedRefLevels[0] = null;
    _selectedRefLevels[1] = null;
    _selectedRefLevels[2] = null;
  }

  // Filtered & Sorted Shlokas getter
  List<LearningShloka> get _processedShlokas {
    List<LearningShloka> list = List.from(_shlokas);

    // Search query filter
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      list = list.where((s) {
        final refMatch = s.reference.toLowerCase().contains(query);
        final textMatch = s.shloka.toLowerCase().contains(query);
        final transMatch =
            s.translation?.toLowerCase().contains(query) ?? false;
        final bookMatch = _getBookName(s.bookId).toLowerCase().contains(query);
        return refMatch || textMatch || transMatch || bookMatch;
      }).toList();
    }

    // Hierarchical reference dropdown filtering
    for (int i = 0; i < 3; i++) {
      final selectedVal = _selectedRefLevels[i];
      if (selectedVal != null) {
        list = list.where((s) {
          final parts = s.reference.split('.');
          return parts.length > i && parts[i] == selectedVal;
        }).toList();
      }
    }

    // Sorting logic
    list.sort((a, b) {
      switch (_sortBy) {
        case ShlokaSortOption.dateNewest:
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        case ShlokaSortOption.dateOldest:
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        case ShlokaSortOption.referenceAsc:
          return _compareReferences(a.reference, b.reference);
        case ShlokaSortOption.referenceDesc:
          return _compareReferences(b.reference, a.reference);
      }
    });

    return list;
  }

  int _compareReferences(String refA, String refB) {
    final partsA = refA.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = refB.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      if (partsA[i] != partsB[i]) {
        return partsA[i].compareTo(partsB[i]);
      }
    }
    return partsA.length.compareTo(partsB.length);
  }

  // ============================================================
  // BOOK DIALOG
  // ============================================================

  Future<void> _showBookDialog({LearningBook? book}) async {
    final nameController = TextEditingController(text: book?.name ?? '');
    int levelCount = book?.levelCount ?? 2;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
              contentPadding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      book == null
                          ? Icons.menu_book_outlined
                          : Icons.edit_outlined,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(book == null ? 'Create Book' : 'Edit Book'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book == null
                            ? 'Create a book to organize your shlokas.'
                            : 'Update the book details below.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 20,
                                color: colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onErrorContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) {
                          if (errorMessage != null) {
                            setDialogState(() {
                              errorMessage = null;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Book name',
                          hintText: 'e.g. Bhagavad Gita',
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest
                              .withOpacity(0.35),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Reference structure',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose how many levels your references should use.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(
                              value: 1,
                              label: Text('1 Level'),
                            ),
                            ButtonSegment<int>(
                              value: 2,
                              label: Text('2 Levels'),
                            ),
                            ButtonSegment<int>(
                              value: 3,
                              label: Text('3 Levels'),
                            ),
                          ],
                          selected: {levelCount},
                          onSelectionChanged: (value) {
                            setDialogState(() {
                              levelCount = value.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Example: ${_referenceExample(levelCount)}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final name = nameController.text.trim();

                    if (name.isEmpty) {
                      setDialogState(() {
                        errorMessage = 'Please enter a book name.';
                      });
                      return;
                    }

                    try {
                      if (book == null) {
                        await _repository.addBook(
                          LearningBook(
                            userId: widget.userId,
                            name: name,
                            levelCount: levelCount,
                            createdAt: DateTime.now(),
                          ),
                        );
                      } else {
                        await _repository.updateBook(
                          book.copyWith(
                            name: name,
                            levelCount: levelCount,
                            updatedAt: DateTime.now(),
                          ),
                        );
                      }

                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext, true);
                    } catch (e) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        errorMessage = e.toString().replaceFirst(
                          'Exception: ',
                          '',
                        );
                      });
                    }
                  },
                  icon: Icon(book == null ? Icons.add : Icons.check),
                  label: Text(book == null ? 'Create Book' : 'Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      await _loadBooks();
    }
  }

  String _referenceExample(int levelCount) {
    switch (levelCount) {
      case 1:
        return '1, 2, 3...';
      case 2:
        return '1.1, 1.2, 2.1...';
      case 3:
        return '1.1.1, 1.1.2, 1.2.1...';
      default:
        return '';
    }
  }

  // ============================================================
  // SHLOKA DIALOG
  // ============================================================

  Future<void> _showShlokaDialog({LearningShloka? shloka}) async {
    LearningBook? targetBook = _selectedBook;

    if (targetBook == null) return;

    if (targetBook.id == -1) {
      if (_books.isEmpty) return;
      targetBook = _books.first;
    }

    final referenceController = TextEditingController(
      text: shloka?.reference ?? '',
    );
    final shlokaController = TextEditingController(text: shloka?.shloka ?? '');
    final translationController = TextEditingController(
      text: shloka?.translation ?? '',
    );
    final urlController = TextEditingController(text: shloka?.url ?? '');

    LearningStatus status = shloka?.status ?? LearningStatus.notLearned;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;

            return _ShlokaDialogContent(
              book: targetBook!,
              shloka: shloka,
              referenceController: referenceController,
              shlokaController: shlokaController,
              translationController: translationController,
              urlController: urlController,
              status: status,
              colorScheme: colorScheme,
              onStatusChanged: (value) {
                setDialogState(() {
                  status = value;
                });
              },
              onSave: ({required String? error}) async {
                if (error != null) return;

                try {
                  if (shloka == null) {
                    await _repository.addShloka(
                      LearningShloka(
                        userId: widget.userId,
                        bookId: targetBook!.id!,
                        reference: referenceController.text.trim(),
                        shloka: shlokaController.text.trim(),
                        translation: translationController.text.trim().isEmpty
                            ? null
                            : translationController.text.trim(),
                        url: urlController.text.trim().isEmpty
                            ? null
                            : urlController.text.trim(),
                        status: status,
                        createdAt: DateTime.now(),
                      ),
                    );
                  } else {
                    await _repository.updateShloka(
                      shloka.copyWith(
                        reference: referenceController.text.trim(),
                        shloka: shlokaController.text.trim(),
                        translation: translationController.text.trim().isEmpty
                            ? null
                            : translationController.text.trim(),
                        url: urlController.text.trim().isEmpty
                            ? null
                            : urlController.text.trim(),
                        status: status,
                        updatedAt: DateTime.now(),
                      ),
                    );
                  }

                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, true);
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().replaceFirst('Exception: ', ''),
                      ),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );

    if (result == true) {
      await _loadShlokas();
    }
  }

  // ============================================================
  // STATUS & DELETE
  // ============================================================

  Future<void> _changeStatus(
    LearningShloka shloka,
    LearningStatus status,
  ) async {
    try {
      await _repository.updateStatus(shlokaId: shloka.id!, status: status);
      await _loadShlokas();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteShloka(LearningShloka shloka) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Delete Shloka?')),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete ${shloka.reference}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteShloka(shloka.id!);
      await _loadShlokas();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteBook(LearningBook book) async {
    if (book.id == -1) return;

    if (book.name.trim().toLowerCase() == 'others') {
      _showError('The Others book cannot be deleted.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_forever_outlined,
                  color: colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Delete Book?')),
            ],
          ),
          content: Text(
            'All shlokas inside "${book.name}" will also be deleted.\n\nThis action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete Book'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _repository.deleteBook(book.id!);

      if (!mounted) return;

      setState(() {
        _selectedBook = null;
        _filter = null;
      });

      await _loadBooks();
    } catch (e) {
      _showError(e.toString());
    }
  }

  // ============================================================
  // OPEN URL & HELPERS
  // ============================================================

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError('Invalid URL.');
      return;
    }

    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showError('Could not open URL.');
      }
    } catch (_) {
      _showError('Could not open URL.');
    }
  }

  Color _statusColor(BuildContext context, LearningStatus status) {
    switch (status) {
      case LearningStatus.notLearned:
        return Colors.grey;
      case LearningStatus.learning:
        return Colors.blue;
      case LearningStatus.needRevision:
        return Colors.orange;
      case LearningStatus.memorized:
        return Colors.green;
    }
  }

  Color _statusContainerColor(BuildContext context, LearningStatus status) {
    return _statusColor(context, status).withOpacity(0.12);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message.replaceFirst('Exception: ', '')),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 20,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search ref, shloka, or book...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              )
            : const Text(
                'Learning Tracker',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'Close Search' : 'Search Shlokas',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            tooltip: _showTranslation
                ? 'Hide translations'
                : 'Show translations',
            onPressed: () {
              setState(() {
                _showTranslation = !_showTranslation;
              });
            },
            icon: Icon(
              _showTranslation ? Icons.translate : Icons.translate_outlined,
            ),
          ),
          if (_selectedBook != null && _selectedBook!.id != -1)
            _buildBookMenu(),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildBookHeader(),
                        _buildReferenceDropdowns(),
                        _buildFiltersAndSortingBar(),
                      ],
                    ),
                  ),
                  _buildShlokaListSliver(),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // BOOK MENU
  // ============================================================

  Widget _buildBookMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Book options',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        final book = _selectedBook;
        if (book == null || book.id == -1) return;

        if (value == 'edit') {
          _showBookDialog(book: book);
        }
        if (value == 'delete') {
          _deleteBook(book);
        }
      },
      itemBuilder: (context) {
        final isOthers = _selectedBook!.name.trim().toLowerCase() == 'others';

        return [
          const PopupMenuItem<String>(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit book'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (!isOthers)
            const PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Delete book'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ];
      },
    );
  }

  // ============================================================
  // FAB
  // ============================================================

  Widget _buildFloatingActionButton() {
    if (_books.isEmpty) {
      return FloatingActionButton.extended(
        heroTag: 'add_book_fab',
        onPressed: () => _showBookDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Book'),
      );
    }

    return FloatingActionButton.extended(
      heroTag: 'add_shloka_fab',
      onPressed: () => _showShlokaDialog(),
      icon: const Icon(Icons.add),
      label: const Text('Add Shloka'),
    );
  }

  // ============================================================
  // BOOK HEADER WITH "ALL BOOKS" OPTION
  // ============================================================

  Widget _buildBookHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    final dropdownItems = [_allBooksOption, ..._books];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.45),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _selectedBook?.id == -1
                    ? Icons.collections_bookmark_outlined
                    : Icons.menu_book_outlined,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedBook?.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Current Book',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                items: dropdownItems
                    .map(
                      (book) => DropdownMenuItem<int>(
                        value: book.id,
                        child: Text(
                          book.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: book.id == -1
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) async {
                  if (id == null) return;

                  final selected = dropdownItems.firstWhere((b) => b.id == id);

                  setState(() {
                    _selectedBook = selected;
                    _filter = null;
                    _resetRefLevels();
                  });

                  await _saveLastBookId(selected.id);
                  await _loadShlokas();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Create new book',
              onPressed: () => _showBookDialog(),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HIERARCHICAL REFERENCE DROPDOWNS
  // ============================================================

  Widget _buildReferenceDropdowns() {
    if (_shlokas.isEmpty) return const SizedBox.shrink();

    int maxLevels = 1;
    if (_selectedBook != null && _selectedBook!.id != -1) {
      maxLevels = _selectedBook!.levelCount;
    } else {
      // Find max levels across all shlokas in list
      for (final s in _shlokas) {
        final partsCount = s.reference.split('.').length;
        if (partsCount > maxLevels) maxLevels = partsCount;
      }
    }

    if (maxLevels <= 1) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    // Determine available values level by level based on current selections
    List<List<String>> availableLevels = [];

    List<LearningShloka> currentPool = List.from(_shlokas);

    for (int lvl = 0; lvl < maxLevels; lvl++) {
      final Set<String> uniqueVals = {};
      for (final s in currentPool) {
        final parts = s.reference.split('.');
        if (parts.length > lvl) {
          uniqueVals.add(parts[lvl]);
        }
      }

      final sortedList = uniqueVals.toList()
        ..sort((a, b) {
          final intA = int.tryParse(a) ?? 0;
          final intB = int.tryParse(b) ?? 0;
          return intA.compareTo(intB);
        });

      availableLevels.add(sortedList);

      final selectedVal = _selectedRefLevels[lvl];
      if (selectedVal != null) {
        currentPool = currentPool.where((s) {
          final parts = s.reference.split('.');
          return parts.length > lvl && parts[lvl] == selectedVal;
        }).toList();
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Reference Filter',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                if (_selectedRefLevels.any((e) => e != null))
                  InkWell(
                    onTap: () {
                      setState(() {
                        _resetRefLevels();
                      });
                    },
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(maxLevels, (index) {
                  final options = availableLevels[index];
                  final currentVal = _selectedRefLevels[index];

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String?>(
                        value: options.contains(currentVal) ? currentVal : null,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Lvl ${index + 1}',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All', style: TextStyle(fontSize: 13)),
                          ),
                          ...options.map(
                            (val) => DropdownMenuItem<String?>(
                              value: val,
                              child: Text(
                                val,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedRefLevels[index] = val;
                            // Clear deeper levels when higher level changes
                            for (int k = index + 1; k < 3; k++) {
                              _selectedRefLevels[k] = null;
                            }
                          });
                        },
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FILTERS, COUNTER & SORTING
  // ============================================================

  Widget _buildFiltersAndSortingBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final processedList = _processedShlokas;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              // Count badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${processedList.length} Shlokas',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              // Sort menu button
              PopupMenuButton<ShlokaSortOption>(
                tooltip: 'Sort Options',
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sort, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Sort',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                onSelected: (option) {
                  setState(() {
                    _sortBy = option;
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: ShlokaSortOption.referenceAsc,
                    child: Text('Reference (1 -> 9)'),
                  ),
                  const PopupMenuItem(
                    value: ShlokaSortOption.referenceDesc,
                    child: Text('Reference (9 -> 1)'),
                  ),
                  const PopupMenuItem(
                    value: ShlokaSortOption.dateNewest,
                    child: Text('Date Added (Newest First)'),
                  ),
                  const PopupMenuItem(
                    value: ShlokaSortOption.dateOldest,
                    child: Text('Date Added (Oldest First)'),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(
                  label: 'All',
                  selected: _filter == null,
                  icon: const Icon(Icons.apps_outlined, size: 18),
                  onTap: () async {
                    setState(() => _filter = null);
                    await _loadShlokas();
                  },
                ),
                ...LearningStatus.values.map(
                  (status) => _filterChip(
                    label: status.label,
                    selected: _filter == status,
                    icon: Text(
                      status.icon,
                      style: const TextStyle(fontSize: 16),
                    ),
                    onTap: () async {
                      setState(() => _filter = status);
                      await _loadShlokas();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        avatar: icon,
        label: Text(label),
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }

  // ============================================================
  // SHLOKA LIST SLIVER
  // ============================================================

  Widget _buildShlokaListSliver() {
    final list = _processedShlokas;

    if (_selectedBook == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(
          icon: Icons.menu_book_outlined,
          title: 'Create your first book',
          subtitle:
              'Add a scripture book to start organizing and learning your shlokas.',
          actionLabel: 'Create Book',
          onAction: () => _showBookDialog(),
        ),
      );
    }

    if (list.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(
          icon: _filter == null
              ? Icons.auto_stories_outlined
              : Icons.filter_alt_off_outlined,
          title: _filter == null ? 'No shlokas found' : 'No matching shlokas',
          subtitle: _filter == null
              ? 'Start building your collection by adding your first shloka.'
              : 'Try another filter or search term.',
          actionLabel: _filter == null ? 'Add Shloka' : 'Clear Filters',
          onAction: () async {
            if (_filter != null ||
                _searchQuery.isNotEmpty ||
                _selectedRefLevels.any((e) => e != null)) {
              setState(() {
                _filter = null;
                _searchQuery = '';
                _searchController.clear();
                _resetRefLevels();
              });
              await _loadShlokas();
            } else {
              await _showShlokaDialog();
            }
          },
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _buildShlokaCard(list[index]),
            ),
          );
        }, childCount: list.length),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SHLOKA CARD (WITH LINE SPACING ENHANCEMENT)
  // ============================================================

  Widget _buildShlokaCard(LearningShloka shloka) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bookName = _getBookName(shloka.bookId);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        shloka.reference,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (_selectedBook?.id == -1) ...[
                      const SizedBox(height: 4),
                      Text(
                        bookName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(child: _statusBadge(shloka.status)),
                _buildStatusMenu(shloka),
                _buildShlokaMenu(shloka),
              ],
            ),
            const SizedBox(height: 18),

            // ----------------------------------------------------
            // SHLOKA DISPLAY (ENHANCED LINE SPACING)
            // ----------------------------------------------------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.28),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                shloka.shloka,
                style: theme.textTheme.bodyLarge?.copyWith(
                  // height: 2.1,
                  fontSize: 16,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            if (_showTranslation &&
                shloka.translation != null &&
                shloka.translation!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.translate_outlined,
                          size: 18,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Translation',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      shloka.translation!,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STATUS BADGE & MENUS
  // ============================================================

  Widget _statusBadge(LearningStatus status) {
    final color = _statusColor(context, status);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: _statusContainerColor(context, status),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status.icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                status.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMenu(LearningShloka shloka) {
    return PopupMenuButton<LearningStatus>(
      tooltip: 'Change learning status',
      padding: EdgeInsets.zero,
      icon: Text(shloka.status.icon, style: const TextStyle(fontSize: 21)),
      onSelected: (status) => _changeStatus(shloka, status),
      itemBuilder: (context) {
        return LearningStatus.values
            .map(
              (status) => PopupMenuItem<LearningStatus>(
                value: status,
                child: Row(
                  children: [
                    Text(status.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Text(status.label),
                  ],
                ),
              ),
            )
            .toList();
      },
    );
  }

  Widget _buildShlokaMenu(LearningShloka shloka) {
    final hasUrl = shloka.url != null && shloka.url!.trim().isNotEmpty;

    return PopupMenuButton<String>(
      tooltip: 'More options',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            _showShlokaDialog(shloka: shloka);
            break;
          case 'source':
            if (hasUrl) _openUrl(shloka.url!);
            break;
          case 'delete':
            _deleteShloka(shloka);
            break;
        }
      },
      itemBuilder: (context) {
        return [
          const PopupMenuItem<String>(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (hasUrl)
            const PopupMenuItem<String>(
              value: 'source',
              child: ListTile(
                leading: Icon(Icons.open_in_new_outlined),
                title: Text('Open Source'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          const PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text('Delete'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ];
      },
    );
  }
}

// ============================================================================
// SHLOKA DIALOG CONTENT
// ============================================================================

class _ShlokaDialogContent extends StatefulWidget {
  final LearningBook book;
  final LearningShloka? shloka;

  final TextEditingController referenceController;
  final TextEditingController shlokaController;
  final TextEditingController translationController;
  final TextEditingController urlController;

  final LearningStatus status;
  final ColorScheme colorScheme;

  final ValueChanged<LearningStatus> onStatusChanged;
  final Future<void> Function({required String? error}) onSave;

  const _ShlokaDialogContent({
    required this.book,
    required this.shloka,
    required this.referenceController,
    required this.shlokaController,
    required this.translationController,
    required this.urlController,
    required this.status,
    required this.colorScheme,
    required this.onStatusChanged,
    required this.onSave,
  });

  @override
  State<_ShlokaDialogContent> createState() => _ShlokaDialogContentState();
}

class _ShlokaDialogContentState extends State<_ShlokaDialogContent> {
  String? _formError;
  bool _saving = false;

  String? _validate() {
    final reference = widget.referenceController.text.trim();
    final shloka = widget.shlokaController.text.trim();

    if (reference.isEmpty) return 'Please enter a reference.';
    if (shloka.isEmpty) return 'Please enter the shloka text.';

    final parts = reference.split('.');

    if (parts.length != widget.book.levelCount) {
      return 'Reference must contain ${widget.book.levelCount} level'
          '${widget.book.levelCount == 1 ? '' : 's'}. Example: ${_referenceHint(widget.book.levelCount)}';
    }

    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number <= 0) {
        return 'Reference contains an invalid number.';
      }
    }

    final url = widget.urlController.text.trim();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (!uri.hasScheme ||
              !(uri.scheme == 'http' || uri.scheme == 'https'))) {
        return 'Please enter a valid URL starting with http:// or https://';
      }
    }

    return null;
  }

  String _referenceHint(int levelCount) {
    switch (levelCount) {
      case 1:
        return '1';
      case 2:
        return '1.1';
      case 3:
        return '1.1.1';
      default:
        return '1';
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final error = _validate();
    if (error != null) {
      setState(() => _formError = error);
      return;
    }

    setState(() {
      _formError = null;
      _saving = true;
    });

    try {
      await widget.onSave(error: null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = widget.colorScheme;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.shloka == null
                  ? Icons.auto_stories_outlined
                  : Icons.edit_outlined,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.shloka == null ? 'Add Shloka' : 'Edit Shloka',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.book.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_formError != null) ...[
                _buildErrorBanner(),
                const SizedBox(height: 16),
              ],
              _sectionHeader(
                icon: Icons.info_outline,
                title: 'Basic Information',
                subtitle: 'Enter the reference and shloka text.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: widget.referenceController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Reference',
                  hintText: _referenceHint(widget.book.levelCount),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(
                    0.35,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _referenceInfo(),
              const SizedBox(height: 16),
              TextField(
                controller: widget.shlokaController,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                minLines: 4,
                maxLines: 8,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                decoration: InputDecoration(
                  labelText: 'Shloka',
                  hintText: 'Enter the complete shloka here...',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(
                    0.35,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionHeader(
                icon: Icons.notes_outlined,
                title: 'Additional Information',
                subtitle: 'Translation and source are optional.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: widget.translationController,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 6,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                decoration: InputDecoration(
                  labelText: 'Translation',
                  hintText: 'Enter the translation...',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(
                    0.35,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: widget.urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Source URL',
                  hintText: 'https://example.com/...',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(
                    0.35,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  helperText: 'Optional. Appears in the shloka options menu.',
                ),
              ),
              const SizedBox(height: 24),
              _sectionHeader(
                icon: Icons.school_outlined,
                title: 'Learning Progress',
                subtitle: 'Set the current learning status.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<LearningStatus>(
                value: widget.status,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Learning status',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(
                    0.35,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                selectedItemBuilder: (BuildContext context) {
                  return LearningStatus.values
                      .map(
                        (value) => Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                value.icon,
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(width: 8),
                              Text(value.label),
                            ],
                          ),
                        ),
                      )
                      .toList();
                },
                items: LearningStatus.values
                    .map(
                      (value) => DropdownMenuItem<LearningStatus>(
                        value: value,
                        child: Row(
                          children: [
                            Text(
                              value.icon,
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(value.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        widget.onStatusChanged(value);
                      },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(widget.shloka == null ? Icons.add : Icons.check),
          label: Text(
            _saving
                ? 'Saving...'
                : widget.shloka == null
                ? 'Add Shloka'
                : 'Save Changes',
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    final colorScheme = widget.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _formError!,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _formError = null),
            icon: Icon(
              Icons.close,
              color: colorScheme.onErrorContainer,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colorScheme = widget.colorScheme;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _referenceInfo() {
    final colorScheme = widget.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 16,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Use ${widget.book.levelCount} level'
              '${widget.book.levelCount == 1 ? '' : 's'} for this book. Example: '
              '${_referenceHint(widget.book.levelCount)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
