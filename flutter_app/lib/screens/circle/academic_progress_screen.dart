import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/json_utils.dart';
import '../../utils/export_utils.dart';

/// يقابل "ج. التقارير والرسوم البيانية" في المواصفات: متابعة الحفظ
/// والمراجعة بمؤشرات بصرية ملونة + رسوم بيانية لمقارنة الطلاب وإحصائيات
/// المجمع الإجمالية ومقارنة الحلقات الفرعية.
/// (getAcademicProgressData + saveAcademicProgressValue في Code.gs)
class AcademicProgressScreen extends StatefulWidget {
  final String circleId;
  final String? filterTeacherId;
  const AcademicProgressScreen({super.key, required this.circleId, this.filterTeacherId});

  @override
  State<AcademicProgressScreen> createState() => _AcademicProgressScreenState();
}

class _AcademicProgressScreenState extends State<AcademicProgressScreen> {
  late Future<void> _loadFuture;
  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _subCircleByStudentId = {};
  List<String> _subCircles = [];
  String? _filterSubCircle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiService>();
    _loadFuture = Future.wait([
      api.getAcademicProgressData(widget.circleId),
      api.getStudents(widget.circleId),
      api.getInitialData(widget.circleId),
    ]).then((results) {
      final progressByStudentId = {
        for (final r in asMapList(results[0]['records'])) (r['studentId']?.toString() ?? ''): r,
      };
      var students = asMapList(results[1]['students']);
      final teachers = asMapList(results[2]['teachers']);
      if (widget.filterTeacherId != null) {
        students = students.where((s) => studentBelongsToTeacher(s, widget.filterTeacherId, teachers)).toList();
      }
      final settings = Map<String, dynamic>.from(results[2]['settings'] as Map? ?? {});
      _subCircles = List<String>.from((settings['subCircles'] as List?) ?? const []);
      _subCircleByStudentId = {
        for (final s in students) (s['id']?.toString() ?? ''): (s['subCircle']?.toString() ?? ''),
      };
      // نبني صفًا لكل طالب في الحلقة (وليس فقط الطلاب اللي عندهم سجل تقدّم
      // موجود مسبقًا)، عشان المعلم يقدر يدخل أول قيمة له بدل ما تفضل الشاشة
      // فاضية للأبد لعدم وجود بيانات.
      _rows = students.map((s) {
        final id = s['id']?.toString() ?? '';
        final existing = progressByStudentId[id];
        return {
          'studentId': id,
          'studentName': s['name']?.toString() ?? '',
          'hifz': existing?['hifz'] ?? 0,
          'minorReview': existing?['minorReview'] ?? 0,
          'majorReview': existing?['majorReview'] ?? 0,
        };
      }).toList();
    });
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

  Future<void> _printProgressChart(List<Map<String, dynamic>> students) async {
    await printTablePdf(
      title: 'الرسم البياني لتقدم الطلاب (الحفظ)',
      headers: ['الطالب', 'الحفظ', 'المراجعة الصغرى', 'المراجعة الكبرى'],
      rows: students
          .map((e) => [
                (e['studentName'] ?? '').toString(),
                ((e['hifz'] ?? 0) as num).toString(),
                ((e['minorReview'] ?? 0) as num).toString(),
                ((e['majorReview'] ?? 0) as num).toString(),
              ])
          .toList(),
    );
  }

  Future<void> _shareProgressChartWhatsApp(List<Map<String, dynamic>> students) async {
    await shareTablePdfWhatsApp(
      title: 'الرسم البياني لتقدم الطلاب (الحفظ)',
      headers: ['الطالب', 'الحفظ', 'المراجعة الصغرى', 'المراجعة الكبرى'],
      rows: students
          .map((e) => [
                (e['studentName'] ?? '').toString(),
                ((e['hifz'] ?? 0) as num).toString(),
                ((e['minorReview'] ?? 0) as num).toString(),
                ((e['majorReview'] ?? 0) as num).toString(),
              ])
          .toList(),
      fileName: 'academic_progress.pdf',
    );
  }

  /// مؤشر لوني: أخضر (أداء جيد) / برتقالي (متوسط) / أحمر (يحتاج متابعة)
  Color _indicatorColor(num value) {
    if (value >= 15) return AppColors.primary;
    if (value >= 5) return AppColors.accentOrange;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('حدث خطأ: ${snapshot.error}'));
        if (_rows.isEmpty) return const Center(child: Text('لا يوجد طلاب في هذه الحلقة بعد.'));

        final rows = _filterSubCircle == null
            ? _rows
            : _rows.where((r) => (_subCircleByStudentId[r['studentId']?.toString()] ?? '') == _filterSubCircle).toList();

        // إحصائيات إجمالي المجمع (أو الحلقة الفرعية المفلترة)
        final avgHifz = rows.isEmpty ? 0.0 : rows.map((r) => (r['hifz'] ?? 0) as num).fold<num>(0, (a, b) => a + b) / rows.length;
        final avgMinor = rows.isEmpty ? 0.0 : rows.map((r) => (r['minorReview'] ?? 0) as num).fold<num>(0, (a, b) => a + b) / rows.length;
        final avgMajor = rows.isEmpty ? 0.0 : rows.map((r) => (r['majorReview'] ?? 0) as num).fold<num>(0, (a, b) => a + b) / rows.length;

        // مقارنة الحلقات الفرعية (متوسط الحفظ لكل حلقة فرعية)
        final Map<String, List<num>> bySubCircle = {};
        for (final r in _rows) {
          final sc = _subCircleByStudentId[r['studentId']?.toString()] ?? 'غير محدد';
          bySubCircle.putIfAbsent(sc.isEmpty ? 'غير محدد' : sc, () => []).add((r['hifz'] ?? 0) as num);
        }

        final topStudents = [...rows]..sort((a, b) => ((b['hifz'] ?? 0) as num).compareTo((a['hifz'] ?? 0) as num));
        final chartStudents = topStudents.take(10).toList();

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_subCircles.isNotEmpty && widget.filterTeacherId == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
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
            const Text('إحصائيات المجمع الإجمالية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _AvgCard(label: 'متوسط الحفظ', value: avgHifz)),
                const SizedBox(width: 8),
                Expanded(child: _AvgCard(label: 'متوسط المراجعة الصغرى', value: avgMinor)),
                const SizedBox(width: 8),
                Expanded(child: _AvgCard(label: 'متوسط المراجعة الكبرى', value: avgMajor)),
              ],
            ),
            const SizedBox(height: 20),
            if (chartStudents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _printProgressChart(chartStudents),
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة الرسم البياني'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _shareProgressChartWhatsApp(chartStudents),
                      icon: const Icon(Icons.chat, color: Colors.green),
                      label: const Text('واتساب'),
                    ),
                  ],
                ),
              ),
            if (chartStudents.isNotEmpty) ...[
              const Text('مقارنة الطلاب (الحفظ)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    barGroups: chartStudents.asMap().entries.map((e) {
                      final v = ((e.value['hifz'] ?? 0) as num).toDouble();
                      return BarChartGroupData(x: e.key, barRods: [
                        BarChartRodData(toY: v, color: _indicatorColor(v), width: 14, borderRadius: BorderRadius.circular(4)),
                      ]);
                    }).toList(),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= chartStudents.length) return const SizedBox.shrink();
                            final name = chartStudents[i]['studentName']?.toString() ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(name.length > 6 ? '${name.substring(0, 6)}…' : name, style: const TextStyle(fontSize: 9)),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (bySubCircle.length > 1) ...[
              const Text('مقارنة الحلقات الفرعية (متوسط الحفظ)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...bySubCircle.entries.map((e) {
                final avg = e.value.fold<num>(0, (a, b) => a + b) / e.value.length;
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(e.key),
                    trailing: Text(avg.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.bold, color: _indicatorColor(avg))),
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],
            const Text('متابعة الحفظ والمراجعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rows.map((r) {
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
                        runSpacing: 8,
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
            }),
          ],
        );
      },
    );
  }

  Widget _progressChip(String label, num value, VoidCallback onTap) {
    final color = _indicatorColor(value);
    return ActionChip(
      label: Text('$label: $value'),
      onPressed: onTap,
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }
}

class _AvgCard extends StatelessWidget {
  final String label;
  final double value;
  const _AvgCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
