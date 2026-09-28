import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services.dart';
import 'models.dart';

/// Class-rep tools: set the next class time so every member of the target
/// year gets a push alert N minutes before it starts.
class ClassRepPage extends StatefulWidget {
  const ClassRepPage({super.key});

  @override
  State<ClassRepPage> createState() => _ClassRepPageState();
}

class _ClassRepPageState extends State<ClassRepPage> {
  Future<List<Map<String, dynamic>>>? _schedulesFuture;
  bool _saving = false;

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime _classTime = DateTime.now().add(const Duration(hours: 1));
  int _notifyMinutes = 15;
  bool _repeatWeekly = false;
  int? _targetYear; // null = every user

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _schedulesFuture = context.read<NoteService>().getSchedules());
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _classTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_classTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _classTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the class a name.')));
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<NoteService>().addSchedule(
          title: title,
          classTime: _classTime,
          location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
          notifyMinutesBefore: _notifyMinutes,
          repeatWeekly: _repeatWeekly,
          targetYear: _targetYear,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _titleController.clear();
      _locationController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Class set - $_targetYearYearLabel will be alerted.')),
      );
      _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Only class reps and admins can add classes.')),
      );
    }
  }

  String get _targetYearYearLabel =>
      _targetYear == null ? 'everyone' : 'year $_targetYear students';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Rep Tools', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.campaign_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Set the next class and members of the chosen year get a push alert '
                    'before it starts. Your own note uploads are published to the library '
                    'immediately - no admin review.',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('Next class', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Class name',
              hintText: 'e.g. Database Systems',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.menu_book_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              hintText: 'e.g. Lecture Hall 3',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'When',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.event_rounded),
              ),
              child: Text(_classTime.toString().substring(0, 16)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _notifyMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Alert before',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notifications_active_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 min')),
                    DropdownMenuItem(value: 10, child: Text('10 min')),
                    DropdownMenuItem(value: 15, child: Text('15 min')),
                    DropdownMenuItem(value: 30, child: Text('30 min')),
                    DropdownMenuItem(value: 60, child: Text('1 hour')),
                  ],
                  onChanged: (v) => setState(() => _notifyMinutes = v ?? 15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _targetYear,
                  decoration: const InputDecoration(
                    labelText: 'Alert',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Everyone')),
                    DropdownMenuItem(value: 1, child: Text('Year 1')),
                    DropdownMenuItem(value: 2, child: Text('Year 2')),
                    DropdownMenuItem(value: 3, child: Text('Year 3')),
                    DropdownMenuItem(value: 4, child: Text('Year 4')),
                  ],
                  onChanged: (v) => setState(() => _targetYear = v),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeat every week'),
            subtitle: const Text('Re-arms after each alert so next week fires too'),
            value: _repeatWeekly,
            onChanged: (v) => setState(() => _repeatWeekly = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.alarm_add_rounded),
              label: const Text('Set class alert'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text('Scheduled', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _schedulesFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('No classes scheduled yet.',
                      style: TextStyle(color: theme.hintColor)),
                );
              }
              return Column(
                children: items.map((s) {
                  final when = DateTime.tryParse('${s['class_time']}');
                  final mine = s['created_by'] == context.read<AuthService>().currentUser?.id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(Icons.event_rounded, color: theme.colorScheme.primary),
                      title: Text('${s['title']}'),
                      subtitle: Text([
                        if (when != null) when.toString().substring(0, 16),
                        if ((s['location'] ?? '').toString().isNotEmpty) s['location'],
                        'Alert ${s['notify_minutes_before']} min before',
                        if (s['target_year'] != null) 'Year ${s['target_year']}',
                        if (s['repeat_weekly'] == true) 'Weekly',
                      ].join('  ·  ')),
                      trailing: mine || context.read<AuthService>().currentUser?.hasRole(UserRole.admin) == true
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await context.read<NoteService>().deleteSchedule('${s['id']}');
                                if (ok) _reload();
                              },
                            )
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
