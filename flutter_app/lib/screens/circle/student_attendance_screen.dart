import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';

/// يقابل تحضير الطلاب (getStudents + saveStudentAttendanceDay) في Code.gs
class StudentAttendanceScreen extends StatefulWidget {
  final String circleId;
  const StudentAttendanceScreen({super.key, required this.circleId});

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  late Future<List<Map<String, dynamic>>> _studentsFuture;
  final Map<String, String> _statusByStudentId = {}; // studentId -> 'present' | 'absent'
  bool _saving = false;

  String get _dateKey => intl.DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _studentsFuture = context.read<ApiService>().getStudents(widget.circleId).then((res) {
      final list = (res['students'] as List).cast<Map<String, dynamic>>();
      for (final s in list) {
        _statusByStudentId[s['id']] = 'present';
      }
      return list;
    });
  }

  Future<void> _save(List<Map<String, dynamic>> students) async {
    setState(() => _saving = true);
    try {
      final records = students
          .map((s) => {
                'studentId': s['id'],
                'studentName': s['name'],
                'teacherId': s['teacherId'] ?? '',
                'status': _statusByStudentId[s['id']] ?? 'present',
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
        if (students.isEmpty) {
          return const Center(child: Text('لا يوجد طلاب مسجّلون بعد.'));
        }

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: students.length,
                itemBuilder: (context, i) {
                  final s = students[i];
                  final id = s['id'] as String;
                  final status = _statusByStudentId[id] ?? 'present';
                  return Card(
                    child: ListTile(
                      title: Text(s['name'] ?? ''),
                      subtitle: Text(s['stage'] ?? ''),
                      trailing: ToggleButtons(
                        borderRadius: BorderRadius.circular(8),
                        isSelected: [status == 'present', status == 'absent'],
                        onPressed: (idx) => setState(() {
                          _statusByStudentId[id] = idx == 0 ? 'present' : 'absent';
                        }),
                        children: const [
                          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('حاضر')),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('غائب')),
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
