import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/json_utils.dart';

/// "بياناتي" — شاشة خاصة بالمعلم: ملخّص حضور طلابه اليوم + اتجاه نسبة
/// الحضور العام للمجمع آخر 12 أسبوع (getAttendanceTrend)، تقابل زر
/// "بياناتي" في صفحة المعلم بالتطبيق القديم.
class MyDataScreen extends StatefulWidget {
  final String circleId;
  final String? teacherId;
  const MyDataScreen({super.key, required this.circleId, this.teacherId});

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  late Future<void> _loadFuture;
  bool _loaded = false;

  List<Map<String, dynamic>> _myStudents = [];
  Map<String, String> _todayStatusByStudentId = {};
  List<Map<String, dynamic>> _weeks = [];

  String get _todayKey => intl.DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiService>();
    _loadFuture = Future.wait([
      api.getStudents(widget.circleId),
      api.getStudentAttendanceForDate(widget.circleId, _todayKey),
      api.getAttendanceTrend(widget.circleId),
      api.getInitialData(widget.circleId),
    ]).then((results) {
      final allStudents = asMapList(results[0]['students']);
      final teachers = asMapList(results[3]['teachers']);
      _myStudents = widget.teacherId == null
          ? allStudents
          : allStudents.where((s) => studentBelongsToTeacher(s, widget.teacherId, teachers)).toList();

      final todayRecords = asMapList(results[1]['records']);
      _todayStatusByStudentId = {
        for (final r in todayRecords) r['studentId']?.toString() ?? '': r['status']?.toString() ?? '',
      };

      _weeks = asMapList(results[2]['weeks']);
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _loaded = false;
        setState(_load);
      },
      child: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !_loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && !_loaded) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText('خطأ: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
              ),
            );
          }

          final presentToday = _myStudents
              .where((s) => _todayStatusByStudentId[s['id']?.toString()] == 'present')
              .length;
          final absentToday = _myStudents
              .where((s) => _todayStatusByStudentId[s['id']?.toString()] == 'absent')
              .length;
          final noRecordToday = _myStudents.length - presentToday - absentToday;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('ملخّص طلابي اليوم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'عدد طلابي', value: '${_myStudents.length}', color: AppColors.primary)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatTile(label: 'حاضر اليوم', value: '$presentToday', color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'غائب اليوم', value: '$absentToday', color: AppColors.danger)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatTile(label: 'بدون تسجيل', value: '$noRecordToday', color: Colors.grey)),
                ],
              ),
              const Divider(height: 40),
              const Text('اتجاه نسبة الحضور العام (آخر 12 أسبوع)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('نسبة الحضور لكل طلاب المجمع أسبوعيًا', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              if (_weeks.isEmpty)
                const Text('لا توجد بيانات حضور كافية بعد لعرض الرسم البياني.')
              else
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 100,
                      barTouchData: BarTouchData(enabled: true),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= _weeks.length) return const SizedBox.shrink();
                              final weekStart = _weeks[i]['weekStart']?.toString() ?? '';
                              final shortLabel = weekStart.length >= 5 ? weekStart.substring(5) : weekStart;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(shortLabel, style: const TextStyle(fontSize: 9)),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      barGroups: _weeks.asMap().entries.map((entry) {
                        final rate = (entry.value['attendanceRate'] as num?)?.toDouble() ?? 0;
                        return BarChartGroupData(
                          x: entry.key,
                          barRods: [
                            BarChartRodData(
                              toY: rate,
                              color: AppColors.primary,
                              width: 14,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

