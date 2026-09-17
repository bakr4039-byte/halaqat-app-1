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
  List<String> _subCircles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiService>();
    _leaderboardFuture = Future.wait([
      api.getLeaderboard(widget.circleId),
      api.getInitialData(widget.circleId),
    ]).then((results) {
      final res = results[0];
      final initialRes = results[1];
      final settings = Map<String, dynamic>.from(initialRes['settings'] as Map? ?? {});
      _subCircles = List<String>.from((settings['subCircles'] as List?) ?? const []);
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

    final selectedItemIds = <String>{items.first['id'] as String};
    final selectedStudentIds = <String>{};
    String? filterSubCircle;

    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredStudents = filterSubCircle == null
              ? students
              : students.where((s) => (s['subCircle']?.toString() ?? '') == filterSubCircle).toList();
          return AlertDialog(
          title: const Text('تطبيق نقاط تحفيزية'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(alignment: Alignment.centerRight, child: Text('اختر البنود (يمكن اختيار أكثر من بند):')),
                SizedBox(
                  height: 120,
                  child: ListView(
                    children: items.map((it) {
                      final id = it['id'] as String;
                      return CheckboxListTile(
                        dense: true,
                        title: Text('${it['name']} (${it['type'] == 'grant' ? '+' : '-'}${it['points']})'),
                        value: selectedItemIds.contains(id),
                        onChanged: (checked) => setDialogState(() {
                          if (checked == true) {
                            selectedItemIds.add(id);
                          } else {
                            selectedItemIds.remove(id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                if (_subCircles.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: DropdownButton<String?>(
                      value: filterSubCircle,
                      hint: const Text('فلترة الطلاب بالحلقة الفرعية'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('كل الحلقات')),
                        ..._subCircles.map((sc) => DropdownMenuItem<String?>(value: sc, child: Text(sc))),
                      ],
                      onChanged: (v) => setDialogState(() => filterSubCircle = v),
                    ),
                  ),
                const Align(alignment: Alignment.centerRight, child: Text('اختر الطلاب:')),
                SizedBox(
                  height: 250,
                  child: ListView(
                    children: filteredStudents.map((s) {
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
              onPressed: selectedStudentIds.isEmpty || selectedItemIds.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('تطبيق'),
            ),
          ],
        );
        },
      ),
    );

    if (applied == true && selectedItemIds.isNotEmpty) {
      try {
        for (final itemId in selectedItemIds) {
          await api.applyIncentivePointsBulk(
            circleId: widget.circleId,
            itemId: itemId,
            studentIds: selectedStudentIds.toList(),
            appliedBy: 'app',
          );
        }
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

    String? filterSubCircle;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredLedger = filterSubCircle == null
              ? ledger
              : ledger.where((e) => (e['subCircle']?.toString() ?? '') == filterSubCircle).toList();
          return AlertDialog(
        title: const Text('سجل المنح والخصم'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: error != null
              ? Text(error, style: const TextStyle(color: Colors.red))
              : Column(
                  children: [
                    if (_subCircles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DropdownButton<String?>(
                          value: filterSubCircle,
                          hint: const Text('فلترة بالحلقة الفرعية'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('كل الحلقات')),
                            ..._subCircles.map((sc) => DropdownMenuItem<String?>(value: sc, child: Text(sc))),
                          ],
                          onChanged: (v) => setDialogState(() => filterSubCircle = v),
                        ),
                      ),
                    Expanded(
                      child: filteredLedger.isEmpty
                          ? const Center(child: Text('لا توجد عمليات مسجّلة بعد.'))
                          : ListView.builder(
                              itemCount: filteredLedger.length,
                              itemBuilder: (context, i) {
                                final entry = filteredLedger[i];
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
                  ],
                ),
        ),
        actions: [
          if (filteredLedger.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => printTablePdf(
                title: 'سجل المنح والخصم',
                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                rows: filteredLedger.map(ledgerRow).toList(),
              ),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('طباعة'),
            ),
            TextButton.icon(
              onPressed: () => exportTableExcel(
                sheetTitle: 'سجل المنح والخصم',
                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                rows: filteredLedger.map(ledgerRow).toList(),
                fileName: 'سجل_التحفيز.xlsx',
              ),
              icon: const Icon(Icons.grid_on_outlined, size: 18),
              label: const Text('Excel'),
            ),
        TextButton.icon(
          onPressed: () => shareTablePdfWhatsApp(

                title: 'سجل المنح والخصم',
                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                rows: filteredLedger.map(ledgerRow).toList(),

          ),
          icon: const Icon(Icons.chat, size: 18, color: Colors.green),
          label: const Text('واتساب'),
        ),
          ],
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      );
        },
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
