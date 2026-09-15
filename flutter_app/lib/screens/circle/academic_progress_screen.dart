import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../utils/json_utils.dart';

/// يقابل متابعة الحفظ والمراجعة (getAcademicProgressData + saveAcademicProgressValue) في Code.gs
class AcademicProgressScreen extends StatefulWidget {
  final String circleId;
  const AcademicProgressScreen({super.key, required this.circleId});

  @override
  State<AcademicProgressScreen> createState() => _AcademicProgressScreenState();
}

class _AcademicProgressScreenState extends State<AcademicProgressScreen> {
  late Future<List<Map<String, dynamic>>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _dataFuture = context.read<ApiService>().getAcademicProgressData(widget.circleId).then(
          (res) => asMapList(res['records']),
        );
  }

  Future<void> _updateField(String studentId, String studentName, String field, num currentValue) async {
    final controller = TextEditingController(text: currentValue.toString());
    final newValue = await showDialog<num>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_fieldLabel(field)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'القيمة'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, num.tryParse(controller.text) ?? currentValue),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newValue == null) return;

    await context.read<ApiService>().saveAcademicProgressValue(
          circleId: widget.circleId,
          studentId: studentId,
          studentName: studentName,
          field: field,
          value: newValue,
        );
    if (mounted) setState(_load);
  }

  String _fieldLabel(String field) => switch (field) {
        'hifz' => 'الحفظ',
        'minorReview' => 'المراجعة الصغرى',
        'majorReview' => 'المراجعة الكبرى',
        _ => field,
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('حدث خطأ: ${snapshot.error}'));

        final rows = snapshot.data!;
        if (rows.isEmpty) return const Center(child: Text('لا توجد بيانات تقدّم بعد.'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final r = rows[i];
            final id = r['studentId'] as String;
            final name = r['studentName'] ?? '';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _progressChip('حفظ', r['hifz'] ?? 0, () => _updateField(id, name, 'hifz', r['hifz'] ?? 0)),
                        _progressChip('مراجعة صغرى', r['minorReview'] ?? 0, () => _updateField(id, name, 'minorReview', r['minorReview'] ?? 0)),
                        _progressChip('مراجعة كبرى', r['majorReview'] ?? 0, () => _updateField(id, name, 'majorReview', r['majorReview'] ?? 0)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _progressChip(String label, num value, VoidCallback onTap) {
    return ActionChip(
      label: Text('$label: $value'),
      onPressed: onTap,
      avatar: const Icon(Icons.edit, size: 16),
    );
  }
}
