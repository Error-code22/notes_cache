import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../profile_page.dart';
import '../services.dart';
import '../taxonomy_service.dart';

/// A reusable course/unit selector for the upload and donation flows.
///
/// School and programme come from the signed-in user's profile (they are
/// read-only here because only admins may change them). Stage/year and
/// semester default to the profile stage but can be adjusted so past-paper
/// donations can be filed against the stage they were taken in.
class UnitPicker extends StatefulWidget {
  final bool enabled;
  final ValueChanged<ProgrammeUnit?>? onUnitChanged;
  final ValueChanged<AcademicPeriod?>? onPeriodChanged;
  final ValueChanged<Programme?>? onProgrammeChanged;

  const UnitPicker({
    super.key,
    this.enabled = true,
    this.onUnitChanged,
    this.onPeriodChanged,
    this.onProgrammeChanged,
  });

  @override
  State<UnitPicker> createState() => _UnitPickerState();
}

class _UnitPickerState extends State<UnitPicker> {
  final TaxonomyService _taxonomy = TaxonomyService();

  bool _loading = true;
  String? _error;
  bool _missingProgramme = false;

  School? _school;
  Programme? _programme;
  List<AcademicPeriod> _periods = const [];
  AcademicPeriod? _selectedPeriod;

  List<ProgrammeUnit> _units = const [];
  ProgrammeUnit? _selectedUnit;
  bool _unitsLoading = false;
  String? _unitsError;

  int _stageYear = 1;
  int _stageSemester = 1;

  /// Guards against an older unit request overwriting a newer one.
  int _unitsRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthService>().currentUser;
    if (!mounted) return;

    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to choose your programme and unit.';
      });
      return;
    }

    final programmeId = user.programmeId;
    if (programmeId == null || programmeId.isEmpty) {
      setState(() {
        _loading = false;
        _missingProgramme = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _missingProgramme = false;
    });

    try {
      final periods = await _taxonomy.getPeriods();

      School? school;
      Programme? programme;
      final schools = await _taxonomy.getSchools();
      for (final candidate in schools) {
        if (user.schoolId != null && candidate.id == user.schoolId) {
          school = candidate;
          break;
        }
      }

      if (school != null) {
        final programmes = await _taxonomy.getProgrammes(school.id);
        programme = _findProgramme(programmes, programmeId);
      } else {
        // Legacy profiles may lack school_id. Search the catalogue so an
        // existing programme assignment still resolves.
        for (final candidate in schools) {
          final programmes = await _taxonomy.getProgrammes(candidate.id);
          final match = _findProgramme(programmes, programmeId);
          if (match != null) {
            school = candidate;
            programme = match;
            break;
          }
        }
      }

      if (!mounted) return;

      if (programme == null) {
        setState(() {
          _loading = false;
          _error =
              'Your programme could not be found in the catalogue. Open your profile and choose it again.';
        });
        return;
      }

      AcademicPeriod? period;
      for (final candidate in periods) {
        if (candidate.isCurrent) {
          period = candidate;
          break;
        }
      }
      if (period == null && user.currentPeriodId != null) {
        for (final candidate in periods) {
          if (candidate.id == user.currentPeriodId) {
            period = candidate;
            break;
          }
        }
      }
      if (period == null && periods.isNotEmpty) period = periods.first;

      final year = (user.yearLevel ?? 1).clamp(1, 6).toInt();
      final semester = (user.stageSemester ?? 1).clamp(1, 3).toInt();

      setState(() {
        _loading = false;
        _school = school;
        _programme = programme;
        _periods = periods;
        _selectedPeriod = period;
        _stageYear = year;
        _stageSemester = semester;
      });

      widget.onProgrammeChanged?.call(programme);
      widget.onPeriodChanged?.call(period);
      await _loadUnits();
    } catch (e) {
      debugPrint('UnitPicker: failed to load taxonomy: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your programme units. Check your connection and try again.';
      });
    }
  }

  Programme? _findProgramme(List<Programme> programmes, String id) {
    for (final programme in programmes) {
      if (programme.id == id) return programme;
    }
    return null;
  }

  Future<void> _loadUnits() async {
    final programme = _programme;
    if (programme == null) return;

    final request = ++_unitsRequest;
    setState(() {
      _unitsLoading = true;
      _unitsError = null;
      _units = const [];
      _selectedUnit = null;
    });
    widget.onUnitChanged?.call(null);

    try {
      final units = await _taxonomy.getProgrammeUnits(
        programme.id,
        stageYear: _stageYear,
        stageSemester: _stageSemester,
      );
      if (!mounted || request != _unitsRequest) return;
      setState(() {
        _units = units;
        _unitsLoading = false;
      });
    } catch (e) {
      debugPrint('UnitPicker: failed to load units: $e');
      if (!mounted || request != _unitsRequest) return;
      setState(() {
        _unitsLoading = false;
        _unitsError = 'Could not load units for this stage.';
      });
    }
  }

  void _onStageChanged({int? year, int? semester}) {
    setState(() {
      if (year != null) _stageYear = year;
      if (semester != null) _stageSemester = semester;
    });
    _loadUnits();
  }

  void _onUnitChanged(String? id) {
    ProgrammeUnit? unit;
    if (id != null) {
      for (final candidate in _units) {
        if (candidate.id == id) {
          unit = candidate;
          break;
        }
      }
    }
    setState(() => _selectedUnit = unit);
    widget.onUnitChanged?.call(unit);
  }

  void _onPeriodChanged(String? id) {
    AcademicPeriod? period;
    if (id != null) {
      for (final candidate in _periods) {
        if (candidate.id == id) {
          period = candidate;
          break;
        }
      }
    }
    setState(() => _selectedPeriod = period);
    widget.onPeriodChanged?.call(period);
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfilePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return _stateCard(
        theme,
        icon: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        title: 'Loading your programme',
        message: 'Fetching schools, units and academic periods…',
      );
    }

    if (_missingProgramme) {
      return _stateCard(
        theme,
        icon: Icon(Icons.school_outlined, color: theme.colorScheme.primary, size: 34),
        title: 'Set up your programme first',
        message:
            'Choose your school, programme and stage in your profile before uploading or donating notes.',
        action: FilledButton.icon(
          onPressed: _openProfile,
          icon: const Icon(Icons.person_outline),
          label: const Text('Open profile'),
        ),
      );
    }

    if (_error != null) {
      return _stateCard(
        theme,
        icon: const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 34),
        title: 'Course details unavailable',
        message: _error!,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }

    final provisional = _selectedUnit?.isProvisional == true;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _readOnlyRow(theme, Icons.account_balance_outlined, 'School', _school?.name ?? 'Not set'),
            const SizedBox(height: 12),
            _readOnlyRow(
              theme,
              Icons.workspaces_outline,
              'Programme',
              _programme == null
                  ? 'Not set'
                  : '${_programme!.code} — ${_programme!.name}',
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown<int>(
                    theme,
                    label: 'Stage / Year',
                    value: _stageYear,
                    items: const [1, 2, 3, 4, 5, 6],
                    labelFor: (year) => 'Year $year',
                    onChanged: widget.enabled
                        ? (value) {
                            if (value != null) _onStageChanged(year: value);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown<int>(
                    theme,
                    label: 'Semester',
                    value: _stageSemester,
                    items: const [1, 2, 3],
                    labelFor: (semester) => 'Semester $semester',
                    onChanged: widget.enabled
                        ? (value) {
                            if (value != null) _onStageChanged(semester: value);
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_periods.isEmpty)
              _inlineMessage(
                theme,
                Icons.event_busy_outlined,
                'No academic periods are configured yet. Contact an admin.',
                isError: true,
              )
            else
              _buildDropdown<String>(
                theme,
                label: 'Academic period',
                value: _selectedPeriod?.id,
                items: _periods.map((period) => period.id).toList(),
                labelFor: (id) {
                  for (final period in _periods) {
                    if (period.id == id) return period.label;
                  }
                  return id;
                },
                onChanged: widget.enabled ? _onPeriodChanged : null,
              ),
            const SizedBox(height: 16),
            if (_unitsLoading)
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading units for Year $_stageYear, Semester $_stageSemester…',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              )
            else if (_unitsError != null)
              _inlineMessage(
                theme,
                Icons.error_outline_rounded,
                _unitsError!,
                isError: true,
                action: TextButton(
                  onPressed: _loadUnits,
                  child: const Text('Retry'),
                ),
              )
            else if (_units.isEmpty)
              _inlineMessage(
                theme,
                Icons.inbox_outlined,
                'No units are listed for Year $_stageYear, Semester $_stageSemester in this programme yet.',
              )
            else
              _buildDropdown<String>(
                theme,
                label: 'Unit',
                value: _selectedUnit?.id,
                items: _units.map((unit) => unit.id).toList(),
                labelFor: (id) {
                  for (final unit in _units) {
                    if (unit.id == id) return '${unit.unitCode} — ${unit.unitTitle}';
                  }
                  return id;
                },
                onChanged: widget.enabled ? _onUnitChanged : null,
              ),
            if (provisional) ...[
              const SizedBox(height: 10),
              Chip(
                avatar: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                label: const Text('Provisional unit'),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
                backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.35),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _readOnlyRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.55)),
        const SizedBox(width: 10),
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>(
    ThemeData theme, {
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) labelFor,
    required ValueChanged<T?>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          dropdownColor: theme.cardColor,
          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelFor(item),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _inlineMessage(
    ThemeData theme,
    IconData icon,
    String message, {
    bool isError = false,
    Widget? action,
  }) {
    final color = isError ? Colors.orange : theme.colorScheme.onSurface.withOpacity(0.65);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isError ? Colors.orange : theme.colorScheme.primary).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: color),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _stateCard(
    ThemeData theme, {
    required Widget icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: theme.colorScheme.onSurface.withOpacity(0.65),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
