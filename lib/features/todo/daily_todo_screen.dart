import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyTodoScreen extends StatefulWidget {
  const DailyTodoScreen({super.key});

  @override
  State<DailyTodoScreen> createState() => _DailyTodoScreenState();
}

class _DailyTodoScreenState extends State<DailyTodoScreen> {
  // ============================================================
  // STORAGE
  // ============================================================

  static const String _tasksKey = 'daily_todo_tasks_v2';
  static const String _completionDateKey = 'daily_todo_completion_date_v2';

  // ============================================================
  // DATA
  // ============================================================

  List<_TodoTask> _tasks = [];

  bool _isLoading = true;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  // ============================================================
  // DATE
  // ============================================================

  String get _todayKey {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  String get _formattedDate {
    return DateFormat('EEEE, d MMMM').format(DateTime.now());
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final storedTasks = prefs.getString(_tasksKey);
      final lastCompletionDate = prefs.getString(_completionDateKey);

      List<_TodoTask> loadedTasks = [];

      if (storedTasks != null && storedTasks.isNotEmpty) {
        try {
          final decoded = jsonDecode(storedTasks);

          if (decoded is List) {
            loadedTasks = decoded
                .map(
                  (item) => _TodoTask.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList();
          }
        } catch (e) {
          debugPrint('Error decoding todo tasks: $e');
        }
      }

      // ==========================================================
      // NEW DAY
      // ==========================================================

      if (lastCompletionDate != _todayKey) {
        loadedTasks = loadedTasks
            .map((task) => task.copyWith(completed: false))
            .toList();

        await prefs.setString(_completionDateKey, _todayKey);

        await prefs.setString(
          _tasksKey,
          jsonEncode(loadedTasks.map((task) => task.toJson()).toList()),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = loadedTasks;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading daily todo: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        _tasksKey,
        jsonEncode(_tasks.map((task) => task.toJson()).toList()),
      );

      await prefs.setString(_completionDateKey, _todayKey);
    } catch (e) {
      debugPrint('Error saving todo tasks: $e');
    }
  }

  // ============================================================
  // COUNTS
  // ============================================================

  int get _completedCount {
    return _tasks.where((task) => task.completed).length;
  }

  double get _progress {
    if (_tasks.isEmpty) {
      return 0;
    }

    return _completedCount / _tasks.length;
  }

  // ============================================================
  // TOGGLE
  // ============================================================

  Future<void> _toggleTask(_TodoTask task) async {
    final index = _tasks.indexWhere((item) => item.id == task.id);

    if (index == -1) {
      return;
    }

    setState(() {
      _tasks[index] = _tasks[index].copyWith(
        completed: !_tasks[index].completed,
      );
    });

    await _saveTasks();
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> _deleteTask(_TodoTask task) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete task?'),
          content: Text('Remove "${task.title}" from your daily checklist?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _tasks.removeWhere((item) => item.id == task.id);
    });

    await _saveTasks();
  }

  // ============================================================
  // EDIT
  // ============================================================

  Future<void> _editTask(_TodoTask task) async {
    final result = await _showTaskDialog(existingTask: task);

    if (result == null) {
      return;
    }

    final index = _tasks.indexWhere((item) => item.id == task.id);

    if (index == -1) {
      return;
    }

    setState(() {
      _tasks[index] = result.copyWith(id: task.id, completed: task.completed);
    });

    await _saveTasks();
  }

  // ============================================================
  // ADD
  // ============================================================

  Future<void> _addTask() async {
    final task = await _showTaskDialog();

    if (task == null) {
      return;
    }

    setState(() {
      _tasks.add(task);
    });

    await _saveTasks();
  }

  // ============================================================
  // TEXT INPUT DIALOG HELPER
  // ============================================================

  Future<String?> _showTextInputDialog(
    BuildContext context, {
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // TASK DIALOG
  // ============================================================

  Future<_TodoTask?> _showTaskDialog({_TodoTask? existingTask}) async {
    final titleController = TextEditingController(
      text: existingTask?.title ?? '',
    );
    final descriptionController = TextEditingController(
      text: existingTask?.description ?? '',
    );

    // Pre-defined categories + custom option support
    List<String> categories = ['Morning', 'Day', 'Evening'];
    String selectedCategory = existingTask?.category ?? 'Morning';
    if (!categories.contains(selectedCategory)) {
      categories.add(selectedCategory);
    }

    // Pre-defined emojis + custom option support
    List<String> emojis = [
      '🙏',
      '📿',
      '📖',
      '🪔',
      '🎧',
      '🤝',
      '🧘',
      '🌱',
      '❤️',
      '✨',
      '🛕',
      '☀️',
    ];
    String selectedEmoji = existingTask?.emoji ?? '🙏';
    if (!emojis.contains(selectedEmoji)) {
      emojis.add(selectedEmoji);
    }

    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<_TodoTask>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        existingTask == null ? 'Add Daily Task' : 'Edit Task',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),

                      // TITLE
                      TextFormField(
                        controller: titleController,
                        autofocus: existingTask == null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Task',
                          hintText: 'e.g. Chant 16 rounds',
                          prefixIcon: const Icon(Icons.check_circle_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Please enter a task'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // DESCRIPTION
                      TextFormField(
                        controller: descriptionController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Description (optional)',
                          hintText: 'Add some details',
                          prefixIcon: const Icon(Icons.notes_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // CATEGORY
                      Text(
                        'Category',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...categories.map(
                            (cat) => _buildCategoryChoice(
                              context,
                              label: cat,
                              emoji: cat == 'Morning'
                                  ? '🌅'
                                  : cat == 'Day'
                                  ? '☀️'
                                  : cat == 'Evening'
                                  ? '🌙'
                                  : '🏷️',
                              selected: selectedCategory == cat,
                              onTap: () =>
                                  setSheetState(() => selectedCategory = cat),
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: const Text('Custom'),
                            onPressed: () async {
                              final customCat = await _showTextInputDialog(
                                context,
                                title: 'Add Custom Category',
                                hint: 'Category name',
                              );
                              if (customCat != null &&
                                  customCat.trim().isNotEmpty) {
                                final trimmed = customCat.trim();
                                setSheetState(() {
                                  if (!categories.contains(trimmed)) {
                                    categories.add(trimmed);
                                  }
                                  selectedCategory = trimmed;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ICON
                      Text(
                        'Icon',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...emojis.map((emoji) {
                            final selected = selectedEmoji == emoji;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  setSheetState(() => selectedEmoji = emoji),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                  border: selected
                                      ? Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 23),
                                ),
                              ),
                            );
                          }),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final customEmoji = await _showTextInputDialog(
                                context,
                                title: 'Enter Custom Emoji',
                                hint: 'Paste/Type Emoji (e.g. 🎯)',
                              );
                              if (customEmoji != null &&
                                  customEmoji.trim().isNotEmpty) {
                                final trimmed = customEmoji.trim();
                                setSheetState(() {
                                  if (!emojis.contains(trimmed)) {
                                    emojis.add(trimmed);
                                  }
                                  selectedEmoji = trimmed;
                                });
                              }
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.add_reaction_outlined,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // SAVE
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;
                            final task = _TodoTask(
                              id:
                                  existingTask?.id ??
                                  DateTime.now().microsecondsSinceEpoch
                                      .toString(),
                              title: titleController.text.trim(),
                              description: descriptionController.text.trim(),
                              category: selectedCategory,
                              emoji: selectedEmoji,
                              completed: existingTask?.completed ?? false,
                            );
                            Navigator.pop(sheetContext, task);
                          },
                          icon: Icon(
                            existingTask == null
                                ? Icons.add
                                : Icons.save_outlined,
                          ),
                          label: Text(
                            existingTask == null ? 'Add Task' : 'Save Changes',
                          ),
                        ),
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

    return result;
  }

  // ============================================================
  // CATEGORY CHOICE
  // ============================================================

  Widget _buildCategoryChoice(
    BuildContext context, {
    required String label,
    required String emoji,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: theme.colorScheme.primary)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 17)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CLEAR COMPLETED
  // ============================================================

  Future<void> _clearCompleted() async {
    if (_completedCount == 0) {
      return;
    }

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove completed tasks?'),
          content: Text(
            '$_completedCount completed '
            '${_completedCount == 1 ? 'task' : 'tasks'} '
            'will be removed from your checklist.',
          ),
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
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldClear != true) {
      return;
    }

    setState(() {
      _tasks.removeWhere((task) => task.completed);
    });

    await _saveTasks();
  }

  // ============================================================
  // RESET TODAY
  // ============================================================

  Future<void> _resetToday() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset today?'),
          content: const Text('All tasks will become unchecked for today.'),
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
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) {
      return;
    }

    setState(() {
      _tasks = _tasks.map((task) => task.copyWith(completed: false)).toList();
    });

    await _saveTasks();
  }

  // ============================================================
  // REORDER CATEGORY
  // ============================================================

  Future<void> _reorderCategory(
    String category,
    int oldIndex,
    int newIndex,
  ) async {
    final categoryTasks = _tasks
        .where((task) => task.category == category && !task.completed)
        .toList();

    if (oldIndex < 0 || oldIndex >= categoryTasks.length) {
      return;
    }

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    if (newIndex < 0) {
      newIndex = 0;
    }

    if (newIndex > categoryTasks.length) {
      newIndex = categoryTasks.length;
    }

    final movedTask = categoryTasks.removeAt(oldIndex);

    categoryTasks.insert(newIndex, movedTask);

    final reorderedIds = categoryTasks.map((task) => task.id).toSet();

    final newTasks = <_TodoTask>[];

    int replacementIndex = 0;

    for (final task in _tasks) {
      final isTargetPending = task.category == category && !task.completed;

      if (isTargetPending) {
        newTasks.add(categoryTasks[replacementIndex]);

        replacementIndex++;
      } else {
        newTasks.add(task);
      }
    }

    reorderedIds.length;

    setState(() {
      _tasks = newTasks;
    });

    await _saveTasks();
  }

  // ============================================================
  // TASKS FOR CATEGORY
  // ============================================================

  List<_TodoTask> _tasksForCategory(
    String category, {
    required bool completed,
  }) {
    return _tasks
        .where(
          (task) => task.category == category && task.completed == completed,
        )
        .toList();
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

    // Dynamic category extraction to support custom categories
    final activeCategories = _tasks
        .where((task) => !task.completed)
        .map((task) => task.category)
        .toSet();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily Checklist',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(_formattedDate, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              switch (value) {
                case 'reset':
                  await _resetToday();
                  break;

                case 'clear':
                  await _clearCompleted();
                  break;
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                  value: 'reset',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Reset today'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('Remove completed'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ];
            },
          ),
        ],
      ),

      // ==========================================================
      // BODY
      // ==========================================================
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        child: _tasks.isEmpty
            ? _buildEmptyState(context)
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ------------------------------------------------
                  // PROGRESS
                  // ------------------------------------------------
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: _buildProgressCard(context),
                    ),
                  ),

                  // ------------------------------------------------
                  // TASKS (DYNAMIC CATEGORY LIST)
                  // ------------------------------------------------
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        ...activeCategories.map(
                          (cat) => _buildCategorySection(
                            context,
                            category: cat,
                            emoji: cat == 'Morning'
                                ? '🌅'
                                : cat == 'Day'
                                ? '☀️'
                                : cat == 'Evening'
                                ? '🌙'
                                : '🏷️',
                          ),
                        ),
                        if (_completedCount > 0)
                          _buildCompletedSection(context),
                      ]),
                    ),
                  ),
                ],
              ),
      ),

      // ==========================================================
      // ADD
      // ==========================================================
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTask,
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
    );
  }

  // ============================================================
  // PROGRESS CARD
  // ============================================================

  Widget _buildProgressCard(BuildContext context) {
    final theme = Theme.of(context);

    final percentage = (_progress * 100).round();

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _progress >= 1 ? Icons.check : Icons.checklist_rounded,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _progress >= 1 ? 'All done! 🎉' : 'Today\'s Sadhana',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '$_completedCount of '
                        '${_tasks.length} '
                        'tasks completed',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  '$percentage%',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 9,
                backgroundColor: theme.colorScheme.surface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CATEGORY SECTION
  // ============================================================

  Widget _buildCategorySection(
    BuildContext context, {
    required String category,
    required String emoji,
  }) {
    final pendingTasks = _tasksForCategory(category, completed: false);

    if (pendingTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------
          // CATEGORY HEADER
          // ------------------------------------------------------
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 9),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 19)),

                const SizedBox(width: 8),

                Text(
                  category,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),

                const SizedBox(width: 7),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${pendingTasks.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const Spacer(),

                // ------------------------------------------------
                // DRAG HINT
                // ------------------------------------------------
                Icon(
                  Icons.swap_vert_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),

          // ------------------------------------------------------
          // REORDERABLE LIST
          // ------------------------------------------------------
          _buildReorderableCategory(context, category, pendingTasks),
        ],
      ),
    );
  }

  // ============================================================
  // REORDERABLE CATEGORY
  // ============================================================

  Widget _buildReorderableCategory(
    BuildContext context,
    String category,
    List<_TodoTask> tasks,
  ) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: tasks.length,
      onReorder: (oldIndex, newIndex) {
        _reorderCategory(category, oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final task = tasks[index];

        return Padding(
          key: ValueKey(task.id),
          padding: const EdgeInsets.only(bottom: 9),
          child: _buildTodoCard(context, task, showDragHandle: true),
        );
      },
    );
  }

  // ============================================================
  // TODO CARD
  // ============================================================

  Widget _buildTodoCard(
    BuildContext context,
    _TodoTask task, {
    bool showDragHandle = false,
  }) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('dismiss_${task.id}'),

      direction: DismissDirection.endToStart,

      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Delete task?'),
              content: Text('Delete "${task.title}"?'),
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
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },

      onDismissed: (_) async {
        setState(() {
          _tasks.removeWhere((item) => item.id == task.id);
        });

        await _saveTasks();
      },

      background: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),

      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _toggleTask(task),
          onLongPress: () => _showTaskActions(task),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                // ------------------------------------------------
                // CHECKBOX
                // ------------------------------------------------
                _buildCheckbox(
                  context,
                  completed: task.completed,
                  onTap: () => _toggleTask(task),
                ),

                const SizedBox(width: 12),

                // ------------------------------------------------
                // EMOJI
                // ------------------------------------------------
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(task.emoji, style: const TextStyle(fontSize: 21)),
                ),

                const SizedBox(width: 12),

                // ------------------------------------------------
                // TEXT
                // ------------------------------------------------
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: task.completed
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.completed
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),

                      if (task.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),

                        Text(
                          task.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ------------------------------------------------
                // DRAG HANDLE
                // ------------------------------------------------
                if (showDragHandle) ...[
                  const SizedBox(width: 6),

                  ReorderableDragStartListener(
                    index: _getPendingIndex(task),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ] else ...[
                  // ------------------------------------------------
                  // MENU
                  // ------------------------------------------------
                  IconButton(
                    tooltip: 'Task options',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showTaskActions(task),
                    icon: Icon(
                      Icons.more_vert,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // GET PENDING INDEX
  // ============================================================

  int _getPendingIndex(_TodoTask task) {
    final pendingTasks = _tasksForCategory(task.category, completed: false);

    return pendingTasks.indexWhere((item) => item.id == task.id);
  }

  // ============================================================
  // CHECKBOX
  // ============================================================

  Widget _buildCheckbox(
    BuildContext context, {
    required bool completed,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completed ? theme.colorScheme.primary : Colors.transparent,
          border: Border.all(
            color: completed
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: completed ? 0 : 2,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: completed
              ? Icon(
                  Icons.check,
                  key: const ValueKey('checked'),
                  size: 21,
                  color: theme.colorScheme.onPrimary,
                )
              : const SizedBox(key: ValueKey('unchecked')),
        ),
      ),
    );
  }

  // ============================================================
  // COMPLETED SECTION
  // ============================================================

  Widget _buildCompletedSection(BuildContext context) {
    final theme = Theme.of(context);

    final completedTasks = _tasks.where((task) => task.completed).toList();

    if (completedTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 9),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 19,
                color: theme.colorScheme.primary,
              ),

              const SizedBox(width: 8),

              Text(
                'Completed',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const Spacer(),

              TextButton(
                onPressed: _clearCompleted,
                child: const Text('Clear'),
              ),
            ],
          ),
        ),

        ...completedTasks.map(
          (task) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _buildTodoCard(context, task),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('🙏', style: TextStyle(fontSize: 48)),
            ),

            const SizedBox(height: 20),

            Text(
              'Your day starts here',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Create a simple checklist '
              'for your daily devotional routine.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 22),

            FilledButton.icon(
              onPressed: _addTask,
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Task'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TASK ACTIONS
  // ============================================================

  Future<void> _showTaskActions(_TodoTask task) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit task'),
                onTap: () {
                  Navigator.pop(context, 'edit');
                },
              ),

              ListTile(
                leading: Icon(
                  task.completed ? Icons.undo : Icons.check_circle_outline,
                ),
                title: Text(
                  task.completed ? 'Mark as incomplete' : 'Mark as completed',
                ),
                onTap: () {
                  Navigator.pop(context, 'toggle');
                },
              ),

              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete task'),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () {
                  Navigator.pop(context, 'delete');
                },
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case 'edit':
        await _editTask(task);
        break;

      case 'toggle':
        await _toggleTask(task);
        break;

      case 'delete':
        await _deleteTask(task);
        break;
    }
  }
}

// ============================================================================
// TODO MODEL
// ============================================================================

class _TodoTask {
  final String id;

  final String title;

  final String description;

  final String category;

  final String emoji;

  final bool completed;

  const _TodoTask({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.emoji,
    required this.completed,
  });

  // --------------------------------------------------------------------------
  // COPY
  // --------------------------------------------------------------------------

  _TodoTask copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? emoji,
    bool? completed,
  }) {
    return _TodoTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      emoji: emoji ?? this.emoji,
      completed: completed ?? this.completed,
    );
  }

  // --------------------------------------------------------------------------
  // JSON
  // --------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'emoji': emoji,
      'completed': completed,
    };
  }

  // --------------------------------------------------------------------------
  // FROM JSON
  // --------------------------------------------------------------------------

  factory _TodoTask.fromJson(Map<String, dynamic> json) {
    return _TodoTask(
      id:
          json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),

      title: json['title']?.toString() ?? '',

      description: json['description']?.toString() ?? '',

      category: json['category']?.toString() ?? 'Morning',

      emoji: json['emoji']?.toString() ?? '🙏',

      completed: json['completed'] == true,
    );
  }
}
