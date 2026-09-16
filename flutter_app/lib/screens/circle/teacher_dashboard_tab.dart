import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/hijri.dart';
import '../../utils/json_utils.dart';
import '../../utils/prayer_times.dart';
import '../../utils/whatsapp_launcher.dart';

/// لوحة التحكم الرئيسية لقسم المعلمين — تقابل "أ. لوحة التحكم الرئيسية"
/// و"ب. جدول تسجيل الحضور اليومي للمعلمين" في وثيقة المواصفات:
/// بطاقات الإحصائيات العلوية + جدول الحضور اليومي الكامل بكل أزراره.
class TeacherDashboardTab extends StatefulWidget {
  final String circleId;
  const TeacherDashboardTab({super.key, required this.circleId});

  @override
  State<TeacherDashboardTab> createState() => _TeacherDashboardTabState();
}

class _TeacherDashboardTabState extends State<TeacherDashboardTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _teachers = [];
  Map<String, dynamic> _settings = {};
  List<Map<String, dynamic>> _todayRecords = [];
  PrayerTimesResult? _prayerTimes;
  bool _isHijri = false;
  String _searchQuery = '';
  bool _savingSheet = false;
  String? _sheetMessage;

  String get _dateKey => intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get _dayName => intl.DateFormat('EEEE', 'ar').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      final results = await Future.wait([
        api.getInitialData(widget.circleId),
        api.getTeacherAttendanceReport(circleId: widget.circleId, fromDateKey: _dateKey, toDateKey: _dateKey),
      ]);
      _settings = Map<String, dynamic>.from(results[0]['settings'] as Map? ?? {});
      _teachers = asMapList(results[0]['teachers']);
      _todayRecords = asMapList(results[1]['records']);
      _isHijri = _settings['calendarType'] == 'hijri';

      final city = _settings['prayerCity']?.toString();
      if (city != null && city.trim().isNotEmpty) {
        fetchPrayerTimes(city.trim()).then((res) {
          if (mounted) setState(() => _prayerTimes = res);
        });
      }
    } catch (e) {
      _error = 'فشل تحميل البيانات: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _recordFor(String teacherId) {
    for (final r in _todayRecords) {
      if (r['teacherId']?.toString() == teacherId) return r;
    }
    return null;
  }

  String _fmtTime(dynamic ts) {
    if (ts == null) return '—';
    try {
      DateTime dt;
      if (ts is Map && ts.containsKey('_seconds')) {
        dt = DateTime.fromMillisecondsSinceEpoch((ts['_seconds'] as int) * 1000);
      } else if (ts is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      } else {
        return '—';
      }
      return intl.DateFormat('hh:mm a', 'ar').format(dt);
    } catch (_) {
      return '—';
    }
  }

  Future<void> _stamp(Map<String, dynamic> teacher, String type) async {
    try {
      await context.read<ApiService>().adminStampTeacherAttendance(
            circleId: widget.circleId,
            teacherId: teacher['id'].toString(),
            teacherName: teacher['name']?.toString() ?? '',
            dateKey: _dateKey,
            dayName: _dayName,
            type: type,
          );
      if (mounted) _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
    }
  }

  Future<void> _toggleAbsent(Map<String, dynamic> teacher, bool isAbsent) async {
    try {
      await context.read<ApiService>().setTeacherAbsentToday(
            circleId: widget.circleId,
            teacherId: teacher['id'].toString(),
            teacherName: teacher['name']?.toString() ?? '',
            dateKey: _dateKey,
            dayName: _dayName,
            isAbsent: isAbsent,
          );
      if (mounted) _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
    }
  }

  Future<void> _saveToSheet() async {
    setState(() {
      _savingSheet = true;
      _sheetMessage = null;
    });
    try {
      final res = await context.read<ApiService>().saveTodayAttendanceToSheet(
            circleId: widget.circleId,
            dateKey: _dateKey,
          );
      setState(() => _sheetMessage = res['success'] == true
          ? 'تم حفظ تسجيل اليوم في Google Sheets بنجاح (${res['count'] ?? ''} صف).'
          : (res['message']?.toString() ?? 'حدث خطأ غير متوقع.'));
    } catch (e) {
      setState(() => _sheetMessage = 'فشل الحفظ: $e');
    } finally {
      if (mounted) setState(() => _savingSheet = false);
    }
  }

  void _searchDialog() async {
    final ctrl = TextEditingController(text: _searchQuery);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بحث عن معلم'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'اسم المعلم')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('مسح')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('بحث')),
        ],
      ),
    );
    if (result != null) setState(() => _searchQuery = result.trim());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    final totalTeachers = _teachers.length;
    final presentToday = _todayRecords.where((r) => r['checkIn'] != null && r['isAbsent'] != true).length;
    final lateToday = _todayRecords.where((r) => r['delayStatus'] == 'متأخر').length;
    final prayerSlot = _settings['prayerSlot']?.toString() ?? 'Asr';
    final adhanTime = _prayerTimes?.timings[prayerSlot];
    final cityLabel = _settings['prayerCity']?.toString() ?? '';

    final filteredTeachers = _searchQuery.isEmpty
        ? _teachers
        : _teachers.where((t) => (t['name']?.toString() ?? '').contains(_searchQuery)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // شريط التنقل العلوي
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
              OutlinedButton.icon(onPressed: _searchDialog, icon: const Icon(Icons.search), label: const Text('بحث عن معلم')),
              OutlinedButton.icon(
                onPressed: () => setState(() => _isHijri = !_isHijri),
                icon: const Icon(Icons.calendar_month),
                label: Text(_isHijri ? 'هجري' : 'ميلادي'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _isHijri ? gregorianToHijri(DateTime.now()).toString() : intl.DateFormat('EEEE dd MMMM yyyy', 'ar').format(DateTime.now()),
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // بطاقات الإحصائيات العلوية
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _StatCard(label: 'إجمالي المعلمين', value: '$totalTeachers', icon: Icons.groups, color: AppColors.accentBlue),
              _StatCard(label: 'حضور اليوم', value: '$presentToday', icon: Icons.check_circle, color: AppColors.primary),
              _StatCard(label: 'تأخيرات اليوم', value: '$lateToday', icon: Icons.schedule, color: AppColors.accentOrange),
              _StatCard(
                label: adhanTime != null ? 'أذان ${prayerSlotLabelsArabic[prayerSlot] ?? prayerSlot} - $cityLabel' : 'مؤشر الأذان',
                value: adhanTime ?? '—',
                icon: Icons.mosque,
                color: AppColors.primaryDark,
                small: true,
              ),
            ],
          ),
          const Divider(height: 32),
          const Text('جدول تسجيل الحضور اليومي للمعلمين', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (filteredTeachers.isEmpty) const Text('لا يوجد معلمون بعد.'),
          if (filteredTeachers.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('اسم المعلم')),
                  DataColumn(label: Text('غياب')),
                  DataColumn(label: Text('وقت الحضور')),
                  DataColumn(label: Text('حالة الحضور')),
                  DataColumn(label: Text('دقائق التأخير')),
                  DataColumn(label: Text('وقت الانصراف')),
                  DataColumn(label: Text('حالة الانصراف')),
                  DataColumn(label: Text('واتساب')),
                ],
                rows: filteredTeachers.asMap().entries.map((entry) {
                  final i = entry.key;
                  final t = entry.value;
                  final r = _recordFor(t['id']?.toString() ?? '');
                  final isAbsent = r?['isAbsent'] == true;
                  final hasCheckIn = r?['checkIn'] != null;
                  final hasCheckOut = r?['checkOut'] != null;
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(t['name']?.toString() ?? '')),
                    DataCell(Checkbox(value: isAbsent, onChanged: (v) => _toggleAbsent(t, v ?? false))),
                    DataCell(hasCheckIn
                        ? Text(_fmtTime(r!['checkIn']))
                        : TextButton(onPressed: () => _stamp(t, 'checkIn'), child: const Text('الآن'))),
                    DataCell(Text(r?['delayStatus']?.toString() ?? (hasCheckIn ? 'في الوقت' : '—'))),
                    DataCell(Text('${r?['delayMins'] ?? 0}')),
                    DataCell(!hasCheckIn
                        ? const Text('—')
                        : hasCheckOut
                            ? Text(_fmtTime(r!['checkOut']))
                            : TextButton(onPressed: () => _stamp(t, 'checkOut'), child: const Text('الآن'))),
                    DataCell(Text(r?['earlyStatus']?.toString() ?? '—')),
                    DataCell(IconButton(
                      icon: const Icon(Icons.chat, color: Colors.green),
                      tooltip: 'إرسال واتساب',
                      onPressed: () => openWhatsApp(
                        t['phone']?.toString() ?? '',
                        message: 'تذكير بتسجيل الحضور اليوم في حلقة ${_settings['circleName'] ?? ''}.',
                      ),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          const SizedBox(height: 20),
          if (_sheetMessage != null) ...[
            Text(_sheetMessage!, style: const TextStyle(color: AppColors.primaryDark)),
            const SizedBox(height: 8),
          ],
          ElevatedButton.icon(
            onPressed: _savingSheet ? null : _saveToSheet,
            icon: _savingSheet
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.table_chart),
            label: const Text('حفظ تسجيل اليوم في Google Sheets'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool small;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: small ? 14 : 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
