import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/export_utils.dart';
import '../../utils/json_utils.dart';

/// يقابل لوحة الشرف ونقاط التحفيز (getLeaderboard + applyIncentivePointsBulk) في Code.gs
class IncentivesScreen extends StatefulWidget {
  final String circleId;
  const IncentivesScreen({super.key, required this.circleId});

  @override
  State<IncentivesScreen> createState() => _IncentivesScreenState();
}

class _IncentivesScreenState extends State<IncentivesScreen> {
  late Future<List<Map<String, dynamic>>> _leaderboardFuture;
  List<Map<String, dynamic>> _lastLeaderboard = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _leaderboardFuture = context.read<ApiService>().getLeaderboard(widget.circleId).then((res) {
      final rows = asMapList(res['leaderboard']);
      _lastLeaderboard = rows;
      return rows;
    });
  }

  static const _medalIcons = {1: '🥇', 2: '🥈', 3: '🥉'};

  Future<void> _exportLeaderboardPdf() async {
    await exportTablePdf(
      title: 'لوحة الشرف',
      headers: const ['الترتيب', 'اسم الطالب', 'الحلقة', 'النقاط'],
      rows: _lastLeaderboard
          .asMap()
          .entries
          .map((e) => ['${e.key + 1}', e.value['studentName']?.toString() ?? '', e.value['subCircle']?.toString() ?? '', '${e.value['points'] ?? 0}'])
          .toList(),
      fileName: 'لوحة_الشرف.pdf',
    );
  }

  Future<void> _shareLeaderboardPdfWhatsApp() async {
    await shareTablePdfWhatsApp(

      title: 'لوحة الشرف',
      headers: const ['الترتيب', 'اسم الطالب', 'الحلقة', 'النقاط'],
      rows: _lastLeaderboard
          .asMap()
          .entries
          .map((e) => ['${e.key + 1}', e.value['studentName']?.toString() ?? '', e.value['subCircle']?.toString() ?? '', '${e.value['points'] ?? 0}'])
          .toList(),
      fileName: 'لوحة_الشرف.pdf',
    
    );
  }

  Future<void> _exportLeaderboardExcel() async {
    await exportTableExcel(
      sheetTitle: 'لوحة الشرف',
      headers: const ['الترتيب', 'اسم الطالب', 'الحلقة', 'النقاط'],
      rows: _lastLeaderboard
          .asMap()
          .entries
          .map((e) => ['${e.key + 1}', e.value['studentName']?.toString() ?? '', e.value['subCircle']?.toString() ?? '', '${e.value['points'] ?? 0}'])
          .toList(),
      fileName: 'لوحة_الشرف.xlsx',
    );
  }

  Future<void> _showApplyPointsDialog() async {
    final api = context.read<ApiService>();
    final itemsRes = await api.getIncentiveItems(widget.circleId);
    final studentsRes = await api.getStudents(widget.circleId);
    final items = asMapList(itemsRes['items']);
    final students = asMapList(studentsRes['students']);

    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بنود تحفيزية بعد. أضف بندًا أولاً.')),
      );
      return;
    }

    String? selectedItemId = items.first['id'] as String;
    final selectedStudentIds = <String>{};

    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تطبيق نقاط تحفيزية'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedItemId,
                  decoration: const InputDecoration(labelText: 'البند'),
                  items: items
                      .map((it) => DropdownMenuItem(
                            value: it['id'] as String,
                            child: Text('${it['name']} (${it['type'] == 'grant' ? '+' : '-'}${it['points']})'),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedItemId = v),
                ),
                const SizedBox(height: 12),
                const Align(alignment: Alignment.centerRight, child: Text('اختر الطلاب:')),
                SizedBox(
                  height: 250,
                  child: ListView(
                    children: students.map((s) {
                      final id = s['id'] as String;
                      return CheckboxListTile(
                        title: Text(s['name'] ?? ''),
                        value: selectedStudentIds.contains(id),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            selectedStudentIds.add(id);
                          } else {
                            selectedStudentIds.remove(id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: selectedStudentIds.isEmpty || selectedItemId == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );

    if (applied == true && selectedItemId != null) {
      try {
        await api.applyIncentivePointsBulk(
          circleId: widget.circleId,
          itemId: selectedItemId!,
          studentIds: selectedStudentIds.toList(),
          appliedBy: 'app',
        );
        if (mounted) setState(_load);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التطبيق: $e')));
        }
      }
    }
  }

  Future<void> _showLedgerDialog() async {
    List<Map<String, dynamic>> ledger = [];
    String? error;
    try {
      final res = await context.read<ApiService>().getIncentiveLedger(widget.circleId);
      ledger = asMapList(res['ledger']);
    } catch (e) {
      error = 'فشل تحميل السجل: $e';
    }
    if (!mounted) return;

    List<String> ledgerRow(Map<String, dynamic> e) => [
          e['studentName']?.toString() ?? '',
          e['itemName']?.toString() ?? '',
          e['type'] == 'grant' ? 'منح' : 'خصم',
          '${e['points'] ?? 0}',
        ];

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('سجل المنح والخصم'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: error != null
              ? Text(error, style: const TextStyle(color: Colors.red))
              : ledger.isEmpty
                  ? const Center(child: Text('لا توجد عمليات مسجّلة بعد.'))
                  : ListView.builder(
                      itemCount: ledger.length,
                      itemBuilder: (context, i) {
                        final entry = ledger[i];
                        final isGrant = entry['type'] == 'grant';
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isGrant ? Icons.add_circle_outline : Icons.remove_circle_outline,
                            color: isGrant ? AppColors.primary : AppColors.danger,
                          ),
                          title: Text(entry['studentName']?.toString() ?? ''),
                          subtitle: Text(entry['itemName']?.toString() ?? ''),
                          trailing: Text(
                            '${isGrant ? '+' : '-'}${entry['points']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isGrant ? AppColors.primary : AppColors.danger,
                            ),
                          ),
                        );
                      },
                    ),
        ),
        actions: [
          if (ledger.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => printTablePdf(
                title: 'سجل المنح والخصم',
                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                rows: ledger.map(ledgerRow).toList(),
              ),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('طباعة'),
            ),
            TextButton.icon(
              onPressed: () => exportTableExcel(
                sheetTitle: 'سجل المنح والخصم',
                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                rows: ledger.map(ledgerRow).toList(),
                fileName: 'سجل_التحفيز.xlsx',
              ),
              icon: const Icon(Icons.grid_on_outlined, size: 18),
              label: const Text('Excel'),
            ),
        TextButton.icon(
          onPressed: () => shareTablePdfWhatsApp(

                title: 'سجل المنح والخصم',
                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                rows: ledger.map(ledgerRow).toList(),
              
          ),
          icon: const Icon(Icons.chat, size: 18, color: Colors.green),
          label: const Text('واتساب'),
        ),
          ],
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'ledgerBtn',
            onPressed: _showLedgerDialog,
            icon: const Icon(Icons.history),
            label: const Text('سجل النقاط'),
            backgroundColor: AppColors.accentBlue,
          ),
          FloatingActionButton.extended(
            heroTag: 'exportBtn',
            onPressed: _lastLeaderboard.isEmpty
                ? null
                : () => showModalBottomSheet(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Wrap(children: [
                          ListTile(
                            leading: const Icon(Icons.picture_as_pdf_outlined),
                            title: const Text('طباعة PDF'),
                            onTap: () {
                              Navigator.pop(context);
                              _exportLeaderboardPdf();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.grid_on_outlined),
                            title: const Text('تصدير Excel'),
                            onTap: () {
                              Navigator.pop(context);
                              _exportLeaderboardExcel();
                            },
                          ),
                        
              ListTile(
                leading: const Icon(Icons.chat, color: Colors.green),
                title: const Text('مشاركة واتساب'),
                onTap: () {
                  Navigator.pop(context);
                  _shareLeaderboardPdfWhatsApp();
                },
              ),
            ]),
                      ),
                    ),
            icon: const Icon(Icons.ios_share),
            label: const Text('تصدير'),
            backgroundColor: AppColors.primaryDark,
          ),
          FloatingActionButton.extended(
            heroTag: 'applyPointsBtn',
            onPressed: _showApplyPointsDialog,
            icon: const Icon(Icons.add_reaction_outlined),
            label: const Text('تطبيق نقاط'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_load),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _leaderboardFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return Center(child: Text('حدث خطأ: ${snapshot.error}'));

            final rows = snapshot.data!;
            if (rows.isEmpty) return const Center(child: Text('لا توجد نقاط مسجّلة بعد.'));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final rank = i + 1;
                final medal = _medalIcons[rank];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: rank <= 3 ? AppColors.accentOrange : Colors.grey.shade300,
                      child: medal != null
                          ? Text(medal, style: const TextStyle(fontSize: 18))
                          : Text('$rank', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    title: Text(r['studentName'] ?? ''),
                    subtitle: (r['subCircle']?.toString() ?? '').isNotEmpty ? Text(r['subCircle'].toString()) : null,
                    trailing: Text(
                      '${r['points']} نقطة',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
