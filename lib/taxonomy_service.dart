import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only access to the JOOUST catalogue:
/// school -> programme -> unit offering (stage + semester).
///
/// The catalogue is public (sign-up needs it before the user has a session),
/// so these queries run against the anon key. Results are cached for the
/// session because the catalogue changes rarely and the pickers are opened
/// repeatedly.
class School {
  final String id;
  final String code;
  final String name;

  const School({required this.id, required this.code, required this.name});

  factory School.fromMap(Map<String, dynamic> map) => School(
        id: map['id'] as String,
        code: (map['code'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
      );
}

class Programme {
  final String id;
  final String schoolId;
  final String code;
  final String name;
  final String level;

  const Programme({
    required this.id,
    required this.schoolId,
    required this.code,
    required this.name,
    this.level = 'undergraduate',
  });

  factory Programme.fromMap(Map<String, dynamic> map) => Programme(
        id: map['id'] as String,
        schoolId: (map['school_id'] as String?) ?? '',
        code: (map['code'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        level: (map['level'] as String?) ?? 'undergraduate',
      );
}

class AcademicPeriod {
  final String id;
  final String code;
  final String label;
  final String academicYear;
  final int semester;
  final bool isCurrent;

  const AcademicPeriod({
    required this.id,
    required this.code,
    required this.label,
    required this.academicYear,
    required this.semester,
    required this.isCurrent,
  });

  factory AcademicPeriod.fromMap(Map<String, dynamic> map) => AcademicPeriod(
        id: map['id'] as String,
        code: (map['code'] as String?) ?? '',
        label: (map['label'] as String?) ?? '',
        academicYear: (map['academic_year'] as String?) ?? '',
        semester: (map['semester'] as num?)?.toInt() ?? 1,
        isCurrent: map['is_current'] == true,
      );
}

/// One unit in a programme at a particular stage/semester.
class ProgrammeUnit {
  final String id;
  final String programmeId;
  final String unitId;
  final String unitCode;
  final String unitTitle;
  final int stageYear;
  final int stageSemester;
  final bool isCore;
  final bool isProvisional;

  const ProgrammeUnit({
    required this.id,
    required this.programmeId,
    required this.unitId,
    required this.unitCode,
    required this.unitTitle,
    required this.stageYear,
    required this.stageSemester,
    this.isCore = true,
    this.isProvisional = false,
  });

  String get label => '${unitCode.trim()} — ${unitTitle.trim()}';

  factory ProgrammeUnit.fromMap(Map<String, dynamic> map) {
    dynamic unit = map['units'];
    if (unit is List) {
      unit = unit.isEmpty ? null : unit.first;
    }
    final unitMap = unit is Map ? Map<String, dynamic>.from(unit) : const <String, dynamic>{};
    return ProgrammeUnit(
      id: map['id'] as String,
      programmeId: (map['programme_id'] as String?) ?? '',
      unitId: (map['unit_id'] as String?) ?? '',
      unitCode: (unitMap['code'] as String?) ?? '',
      unitTitle: (unitMap['title'] as String?) ?? '',
      stageYear: (map['stage_year'] as num?)?.toInt() ?? 1,
      stageSemester: (map['stage_semester'] as num?)?.toInt() ?? 1,
      isCore: map['is_core'] != false,
      isProvisional: map['is_provisional'] == true,
    );
  }
}

class TaxonomyService {
  static List<School>? _schoolsCache;
  static final Map<String, List<Programme>> _programmesCache = {};
  static List<AcademicPeriod>? _periodsCache;
  static final Map<String, List<ProgrammeUnit>> _unitsCache = {};

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<School>> getSchools() async {
    final cached = _schoolsCache;
    if (cached != null) return cached;
    try {
      final data = await _db
          .from('schools')
          .select('id, code, name')
          .order('name', ascending: true);
      final schools = (data as List)
          .map((row) => School.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      _schoolsCache = schools;
      return schools;
    } catch (e) {
      debugPrint('TaxonomyService.getSchools: $e');
      return const [];
    }
  }

  Future<List<Programme>> getProgrammes(String schoolId) async {
    if (schoolId.isEmpty) return const [];
    final cached = _programmesCache[schoolId];
    if (cached != null) return cached;
    try {
      final data = await _db
          .from('programmes')
          .select('id, school_id, code, name, level')
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .order('code', ascending: true);
      final programmes = (data as List)
          .map((row) => Programme.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      _programmesCache[schoolId] = programmes;
      return programmes;
    } catch (e) {
      debugPrint('TaxonomyService.getProgrammes: $e');
      return const [];
    }
  }

  Future<List<AcademicPeriod>> getPeriods() async {
    final cached = _periodsCache;
    if (cached != null) return cached;
    try {
      final data = await _db
          .from('academic_periods')
          .select('id, code, label, academic_year, semester, is_current')
          .order('code', ascending: false);
      final periods = (data as List)
          .map((row) => AcademicPeriod.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      _periodsCache = periods;
      return periods;
    } catch (e) {
      debugPrint('TaxonomyService.getPeriods: $e');
      return const [];
    }
  }

  Future<AcademicPeriod?> getCurrentPeriod() async {
    final periods = await getPeriods();
    for (final period in periods) {
      if (period.isCurrent) return period;
    }
    return periods.isEmpty ? null : periods.first;
  }

  Future<List<ProgrammeUnit>> getProgrammeUnits(
    String programmeId, {
    int? stageYear,
    int? stageSemester,
  }) async {
    if (programmeId.isEmpty) return const [];
    final key = '$programmeId|${stageYear ?? 'all'}|${stageSemester ?? 'all'}';
    final cached = _unitsCache[key];
    if (cached != null) return cached;

    try {
      var query = _db
          .from('programme_units')
          .select(
            'id, programme_id, unit_id, stage_year, stage_semester, is_core, is_provisional, '
            'units!inner(code, title)',
          )
          .eq('programme_id', programmeId);
      if (stageYear != null) query = query.eq('stage_year', stageYear);
      if (stageSemester != null) query = query.eq('stage_semester', stageSemester);

      final data = await query.order('stage_year', ascending: true);
      final units = (data as List)
          .map((row) => ProgrammeUnit.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
      units.sort((a, b) {
        final stage = a.stageYear.compareTo(b.stageYear);
        if (stage != 0) return stage;
        final semester = a.stageSemester.compareTo(b.stageSemester);
        if (semester != 0) return semester;
        return a.unitCode.compareTo(b.unitCode);
      });
      _unitsCache[key] = units;
      return units;
    } catch (e) {
      debugPrint('TaxonomyService.getProgrammeUnits: $e');
      return const [];
    }
  }

  Future<ProgrammeUnit?> getProgrammeUnit(String id) async {
    if (id.isEmpty) return null;
    for (final units in _unitsCache.values) {
      for (final unit in units) {
        if (unit.id == id) return unit;
      }
    }
    try {
      final data = await _db
          .from('programme_units')
          .select(
            'id, programme_id, unit_id, stage_year, stage_semester, is_core, is_provisional, '
            'units!inner(code, title)',
          )
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      return ProgrammeUnit.fromMap(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('TaxonomyService.getProgrammeUnit: $e');
      return null;
    }
  }

  /// Drops the session cache. Used after an admin edits the catalogue.
  void clearCache() {
    _schoolsCache = null;
    _programmesCache.clear();
    _periodsCache = null;
    _unitsCache.clear();
  }
}
