import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';

/// يقابل تحضير/انصراف المعلم (recordTeacherCheckIn / recordTeacherCheckOut) في Code.gs
class TeacherCheckinScreen extends StatefulWidget {
  final String circleId;
  const TeacherCheckinScreen({super.key, required this.circleId});

  @override
  State<TeacherCheckinScreen> createState() => _TeacherCheckinScreenState();
}

class _TeacherCheckinScreenState extends State<TeacherCheckinScreen> {
  bool _loading = false;
  String? _message;

  String get _dateKey => intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get _dayName => intl.DateFormat('EEEE', 'ar').format(DateTime.now());

  Future<void> _checkIn() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      // ملاحظة: teacherId/teacherName الحقيقيين لازم ييجوا من بيانات المعلم المسجّل
      // دخوله (بعد ربط حساب Firebase Auth بمستند المعلم في teachers/{id}) —
      // هنا placeholder بسيط لحد ما نربط شاشة "اختيار المعلم" الكاملة.
      final res = await api.recordTeacherCheckIn(
        circleId: widget.circleId,
        teacherId: 'TODO_teacherId',
        teacherName: 'TODO_teacherName',
        dateKey: _dateKey,
        dayName: _dayName,
      );
      setState(() => _message = res['success'] == true ? 'تم تسجيل الحضور بنجاح.' : (res['message'] ?? 'حدث خطأ'));
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkOut() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      final res = await api.recordTeacherCheckOut(
        circleId: widget.circleId,
        teacherId: 'TODO_teacherId',
        dateKey: _dateKey,
      );
      setState(() => _message = res['success'] == true ? 'تم تسجيل الانصراف بنجاح.' : (res['message'] ?? 'حدث خطأ'));
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(intl.DateFormat('EEEE dd MMMM yyyy', 'ar').format(DateTime.now()),
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _checkIn,
                    icon: const Icon(Icons.login),
                    label: const Text('تسجيل حضور'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _checkOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل انصراف'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 20),
              Text(_message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
