import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/export_utils.dart';
import '../../utils/json_utils.dart';
import '../../utils/whatsapp_launcher.dart';

/// يقابل "د. الإحصائيات ومسير الرواتب" و"هـ. التقارير والتصدير" في وثيقة
/// المواصفات: نافذة إحصائيات بفلترة الفترة، جدول مسير الرواتب الشهري مع
/// تحميل PDF، وقائمة التصدير المنسدلة (كشف حضور أسبوعي / مسير رواتب شهري / سجل كامل).
class PayrollExportTab extends StatefulWidget {
  final String circleId;
  const PayrollExportTab({super.key, required this.circleId});

  @override
  State<PayrollExportTab> createState() => _PayrollExportTabState();
}

class _PayrollExportTabState extends State<PayrollExportTab> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  bool _loading = false;
  String? _error;
  bool _applied = false;

  List<Map<String, dynamic>> _attendanceRecords = [];
  List<Map<String, dynamic>> _payrollRows = [];
  bool _exporting = false;

  String _fmt(DateTime d) => intl.DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isFrom ? _fromDate = picked : _toDate = picked);
  }

  Future<void> _applyPeriod() async {
    setState(() {
      _loading = true;
      _error = null;
      _applied = true;
    });
    try {
      final api = context.read<ApiService>();
      final from = _fmt(_fromDate);
      final to = _fmt(_toDate);
      final results = await Future.wait([
        api.getTeacherAttendanceReport(circleId: widget.circleId, fromDateKey: from, toDateKey: to),
        api.getMonthlyPayroll(circleId: widget.circleId, fromDateKey: from, toDateKey: to),
      ]);
      _attendanceRecords = asMapList(results[0]['records']);
      _payrollRows = asMapList(results[1]['rows']);
    } catch (e) {
      _error = 'فشل تحميل الإحصائيات: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadPayrollPdf() async {
    setState(() => _exporting = true);
    try {
      await exportTablePdf(
        title: 'مسير الرواتب الشهري',
        subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
        headers: const ['المعلم', 'الراتب الأساسي', 'الحضور', 'التأخير', 'دقائق التأخير', 'خصم الغياب', 'خصم التأخير', 'المكافآت', 'الصافي'],
        rows: _payrollRows
            .map((r) => [
                  r['teacherName']?.toString() ?? '',
                  '${r['baseSalary'] ?? 0}',
                  '${r['attendanceCount'] ?? 0}',
                  '${r['lateCount'] ?? 0}',
                  '${r['lateMinutesTotal'] ?? 0}',
                  '${r['absenceDeduction'] ?? 0}',
                  '${r['lateDeduction'] ?? 0}',
                  '${r['bonus'] ?? 0}',
                  '${r['net'] ?? 0}',
                ])
            .toList(),
        fileName: 'مسير_الرواتب.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareDownloadPayrollWhatsApp() async {
    await shareTablePdfWhatsApp(

        title: 'مسير الرواتب الشهري',
        subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
        headers: const ['المعلم', 'الراتب الأساسي', 'الحضور', 'التأخير', 'دقائق التأخير', 'خصم الغياب', 'خصم التأخير', 'المكافآت', 'الصافي'],
        rows: _payrollRows
            .map((r) => [
                  r['teacherName']?.toString() ?? '',
                  '${r['baseSalary'] ?? 0}',
                  '${r['attendanceCount'] ?? 0}',
                  '${r['lateCount'] ?? 0}',
                  '${r['lateMinutesTotal'] ?? 0}',
                  '${r['absenceDeduction'] ?? 0}',
                  '${r['lateDeduction'] ?? 0}',
                  '${r['bonus'] ?? 0}',
                  '${r['net'] ?? 0}',
                ])
            .toList(),
        fileName: 'مسير_الرواتب.pdf',
      
    );
  }

  Future<void> _exportWeeklyAttendancePdf() async {
    setState(() => _exporting = true);
    try {
      await exportTablePdf(
        title: 'كشف الحضور الأسبوعي',
        subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
        headers: const ['التاريخ', 'اليوم', 'المعلم', 'الحالة', 'وقت الحضور', 'التأخير (د)', 'وقت الانصراف'],
        rows: _attendanceRecords
            .map((r) => [
                  r['dateKey']?.toString() ?? '',
                  r['dayName']?.toString() ?? '',
                  r['teacherName']?.toString() ?? '',
                  r['isAbsent'] == true ? 'غائب' : 'حاضر',
                  r['delayStatus']?.toString() ?? '',
                  '${r['delayMins'] ?? 0}',
                  r['earlyStatus']?.toString() ?? '',
                ])
            .toList(),
        fileName: 'كشف_الحضور_الأسبوعي.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareWeeklyAttendanceWhatsApp() async {
    await shareTablePdfWhatsApp(

        title: 'كشف الحضور الأسبوعي',
        subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
        headers: const ['التاريخ', 'اليوم', 'المعلم', 'الحالة', 'وقت الحضور', 'التأخير (د)', 'وقت الانصراف'],
        rows: _attendanceRecords
            .map((r) => [
                  r['dateKey']?.toString() ?? '',
                  r['dayName']?.toString() ?? '',
                  r['teacherName']?.toString() ?? '',
                  r['isAbsent'] == true ? 'غائب' : 'حاضر',
                  r['delayStatus']?.toString() ?? '',
                  '${r['delayMins'] ?? 0}',
                  r['earlyStatus']?.toString() ?? '',
                ])
            .toList(),
        fileName: 'كشف_الحضور_الأسبوعي.pdf',
      
    );
  }

  Future<void> _exportFullLogPdf() async {
    setState(() => _exporting = true);
    try {
      await exportTablePdf(
        title: 'السجل الإجمالي الكامل',
        subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
        headers: const ['التاريخ', 'اليوم', 'المعلم', 'الحالة', 'وقت الحضور', 'حالة الحضور', 'التأخير (د)', 'وقت الانصراف', 'حالة الانصراف'],
        rows: _attendanceRecords
            .map((r) => [
                  r['dateKey']?.toString() ?? '',
                  r['dayName']?.toString() ?? '',
                  r['teacherName']?.toString() ?? '',
                  r['isAbsent'] == true ? 'غائب' : 'حاضر',
                  r['checkIn'] != null ? 'مسجّل' : '—',
                  r['delayStatus']?.toString() ?? '',
                  '${r['delayMins'] ?? 0}',
                  r['checkOut'] != null ? 'مسجّل' : '—',
                  r['earlyStatus']?.toString() ?? '',
                ])
            .toList(),
        fileName: 'السجل_الكامل.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareFullLogWhatsApp() async {
    await shareTablePdfWhatsApp(

        title: 'السجل الإجمالي الكامل',
        subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
        headers: const ['التاريخ', 'اليوم', 'المعلم', 'الحالة', 'وقت الحضور', 'حالة الحضور', 'التأخير (د)', 'وقت الانصراف', 'حالة الانصراف'],
        rows: _attendanceRecords
            .map((r) => [
                  r['dateKey']?.toString() ?? '',
                  r['dayName']?.toString() ?? '',
                  r['teacherName']?.toString() ?? '',
                  r['isAbsent'] == true ? 'غائب' : 'حاضر',
                  r['checkIn'] != null ? 'مسجّل' : '—',
                  r['delayStatus']?.toString() ?? '',
                  '${r['delayMins'] ?? 0}',
                  r['checkOut'] != null ? 'مسجّل' : '—',
                  r['earlyStatus']?.toString() ?? '',
                ])
            .toList(),
        fileName: 'السجل_الكامل.pdf',
      
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _attendanceRecords.where((r) => r['isAbsent'] != true).length;
    final absentCount = _attendanceRecords.where((r) => r['isAbsent'] == true).length;
    final lateCount = _attendanceRecords.where((r) => r['delayStatus'] == 'متأخر').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('نافذة الإحصائيات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            PopupMenuButton<String>(
              enabled: !_exporting && _applied,
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'التصدير',
              onSelected: (v) {
                if (v == 'weekly') _exportWeeklyAttendancePdf();
                if (v == 'payroll') _downloadPayrollPdf();
                if (v == 'full') _exportFullLogPdf();
            if (v == 'weekly_wa') _shareWeeklyAttendanceWhatsApp();
            if (v == 'payroll_wa') _shareDownloadPayrollWhatsApp();
            if (v == 'full_wa') _shareFullLogWhatsApp();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'weekly', child: Text('كشف الحضور الأسبوعي (PDF)')),
                PopupMenuItem(value: 'payroll', child: Text('مسير الرواتب الشهري (PDF)')),
                PopupMenuItem(value: 'full', child: Text('السجل الإجمالي الكامل (PDF)')),
              PopupMenuItem(value: 'weekly_wa', child: Text('مشاركة حضور الأسبوعي واتساب')),
              PopupMenuItem(value: 'payroll_wa', child: Text('مشاركة رواتب الشهري واتساب')),
              PopupMenuItem(value: 'full_wa', child: Text('مشاركة السجل الكامل واتساب')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => _pickDate(isFrom: true), child: Text('من: ${_fmt(_fromDate)}'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton(onPressed: () => _pickDate(isFrom: false), child: Text('إلى: ${_fmt(_toDate)}'))),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _loading ? null : _applyPeriod,
          icon: _loading
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.filter_alt),
          label: const Text('تطبيق الفترة'),
        ),
        const SizedBox(height: 20),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_applied && !_loading && _error == null) ...[
          Row(
            children: [
              Expanded(child: _StatMiniCard(label: 'حضور', value: '$presentCount', color: AppColors.primary)),
              const SizedBox(width: 8),
              Expanded(child: _StatMiniCard(label: 'غياب', value: '$absentCount', color: AppColors.danger)),
              const SizedBox(width: 8),
              Expanded(child: _StatMiniCard(label: 'تأخير', value: '$lateCount', color: AppColors.accentOrange)),
            ],
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('مسير الرواتب الشهري', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _exporting ? null : _downloadPayrollPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('تحميل PDF'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_payrollRows.isEmpty) const Text('لا توجد بيانات رواتب في هذه الفترة.'),
          if (_payrollRows.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('المعلم')),
                  DataColumn(label: Text('الراتب الأساسي')),
                  DataColumn(label: Text('الحضور')),
                  DataColumn(label: Text('التأخير')),
                  DataColumn(label: Text('دقائق التأخير')),
                  DataColumn(label: Text('خصم الغياب')),
                  DataColumn(label: Text('خصم التأخير')),
                  DataColumn(label: Text('المكافآت')),
                  DataColumn(label: Text('الصافي')),
                  DataColumn(label: Text('إشعار')),
                ],
                rows: _payrollRows
                    .map((r) => DataRow(cells: [
                          DataCell(Text(r['teacherName']?.toString() ?? '')),
                          DataCell(Text('${r['baseSalary'] ?? 0}')),
                          DataCell(Text('${r['attendanceCount'] ?? 0}')),
                          DataCell(Text('${r['lateCount'] ?? 0}')),
                          DataCell(Text('${r['lateMinutesTotal'] ?? 0}')),
                          DataCell(Text('${r['absenceDeduction'] ?? 0}')),
                          DataCell(Text('${r['lateDeduction'] ?? 0}')),
                          DataCell(Text('${r['bonus'] ?? 0}')),
                          DataCell(Text('${r['net'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(IconButton(
                            icon: const Icon(Icons.chat, color: Colors.green, size: 18),
                            tooltip: 'إرسال مسير الراتب عبر واتساب',
                            onPressed: () async {
                              final phone = r['phone']?.toString().trim() ?? '';
                              if (phone.isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('لا يوجد رقم هاتف مسجَّل للمعلم "${r['teacherName'] ?? ''}". أضف رقم الهاتف من شاشة إدارة المعلمين أولًا.')),
                                  );
                                }
                                return;
                              }
                              final msg = 'مسير راتب ${r['teacherName'] ?? ''} للفترة ${_fmt(_fromDate)} إلى ${_fmt(_toDate)}:\n'
                                  'الراتب الأساسي: ${r['baseSalary'] ?? 0}\n'
                                  'أيام الحضور: ${r['attendanceCount'] ?? 0}\n'
                                  'أيام التأخير: ${r['lateCount'] ?? 0}\n'
                                  'خصم الغياب: ${r['absenceDeduction'] ?? 0}\n'
                                  'خصم التأخير: ${r['lateDeduction'] ?? 0}\n'
                                  'المكافآت: ${r['bonus'] ?? 0}\n'
                                  'الصافي: ${r['net'] ?? 0}';
                              final ok = await openWhatsApp(phone, message: msg);
                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تعذّر فتح واتساب. تأكد من صحة رقم الهاتف ومن تثبيت واتساب على الجهاز.')),
                                );
                              }
                            },
                          )),
                        ]))
                    .toList(),
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _StatMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatMiniCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

