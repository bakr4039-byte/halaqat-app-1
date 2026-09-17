import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/json_utils.dart';

/// يقابل تحضير الطلاب (getStudents + saveStudentAttendanceDay) في Code.gs
/// — لو filterTeacherId متحدد (المعلم بيفتح شاشته)، بتتفلتر القائمة على
/// طلابه هو بس بدل كل طلاب المجمع.
/// الحالات الست: حاضر (أخضر) / غائب (أحمر) / متأخر (برتقالي) / مستأذن / إجازة
/// / بدون تسجيل (الحالة الافتراضية قبل اختيار المعلم لأي حالة).
class StudentAttendanceScreen extends StatefulWidget {
  final String circleId;
  final String? filterTeacherId;
  const StudentAttendanceScreen({super.key, required this.circleId, this.filterTeacherId});

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

const Map<String, String> kAttendanceStatusLabels = {
  'present': 'حاضر',
  'absent': 'غائب',
  'late': 'متأخر',
  'excused': 'مستأذن',
  'leave': 'إجازة',
};

const Map<String, Color> kAttendanceStatusColors = {
  'present': AppColors.primary,
  'absent': AppColors.danger,
  'late': AppColors.accentOrange,
  'excused': AppColors.accentBlue,
  'leave': Colors.purple,
};

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  late Future<List<Map<String, dynamic>>> _studentsFuture;
  final Map<String, String?> _statusByStudentId = {}; // studentId -> status | null (بدون تسجيل)
  bool _saving = false;
  List<String> _subCircles = [];
  String? _filterSubCircle;

  String get _dateKey => intl.DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiService>();
    _studentsFuture = Future.wait([
      api.getStudents(widget.circleId),
      api.getInitialData(widget.circleId),
    ]).then((results) {
      final res = results[0];
      final initialRes = results[1];
      final settings = Map<String, dynamic>.from(initialRes['settings'] as Map? ?? {});
      _subCircles = List<String>.from((settings['subCircles'] as List?) ?? const []);
      var list = asMapList(res['students']);
      if (widget.filterTeacherId != null) {
        list = list.where((s) => s['teacherId']?.toString() == widget.filterTeacherId).toList();
      }
      for (final s in list) {
        _statusByStudentId[s['id']] = null;
      }
      return list;
    });
  }

  Future<void> _save(List<Map<String, dynamic>> students) async {
    setState(() => _saving = true);
    try {
      final records = students
          .where((s) => _statusByStudentId[s['id']] != null)
          .map((s) => {
                'studentId': s['id'],
                'studentName': s['name'],
                'teacherId': s['teacherId'] ?? '',
                'status': _statusByStudentId[s['id']],
              })
          .toList();

      await context.read<ApiService>().saveStudentAttendanceDay(
            circleId: widget.circleId,
            dateKey: _dateKey,
            records: records,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ تحضير اليوم بنجاح.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _studentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('حدث خطأ: ${snapshot.error}'));

        final students = snapshot.data!;
        final filtered = _filterSubCircle == null
            ? students
            : students.where((s) => (s['subCircle']?.toString() ?? '') == _filterSubCircle).toList();
        if (students.isEmpty) {
          return const Center(child: Text('لا يوجد طلاب مسجّلون بعد.'));
        }

        return Column(
          children: [
            if (_subCircles.isNotEmpty && widget.filterTeacherId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DropdownButton<String?>(
                    value: _filterSubCircle,
                    hint: const Text('فلترة بالحلقة الفرعية'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('كل الحلقات')),
                      ..._subCircles.map((sc) => DropdownMenuItem<String?>(value: sc, child: Text(sc))),
                    ],
                    onChanged: (v) => setState(() => _filterSubCircle = v),
                  ),
                ),
              ),
            if (filtered.isEmpty)
              const Expanded(child: Center(child: Text('لا يوجد طلاب في هذه الحلقة الفرعية.')))
            else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final s = filtered[i];
                  final id = s['id'] as String;
                  final status = _statusByStudentId[id];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          if ((s['stage'] ?? '').toString().isNotEmpty)
                            Text(s['stage'].toString(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: kAttendanceStatusLabels.entries.map((e) {
                              final selected = status == e.key;
                              final color = kAttendanceStatusColors[e.key]!;
                              return ChoiceChip(
                                label: Text(e.value),
                                selected: selected,
                                selectedColor: color,
                                labelStyle: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w600),
                                backgroundColor: color.withValues(alpha: 0.1),
                                onSelected: (_) => setState(() => _statusByStudentId[id] = selected ? null : e.key),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : () => _save(students),
                  icon: _saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'جاري الحفظ...' : 'حفظ تحضير اليوم'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
