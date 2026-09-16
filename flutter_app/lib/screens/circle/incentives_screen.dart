import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _leaderboardFuture = context.read<ApiService>().getLeaderboard(widget.circleId).then(
          (res) => asMapList(res['leaderboard']),
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

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('سجل النقاط'),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'ledgerBtn',
            onPressed: _showLedgerDialog,
            icon: const Icon(Icons.history),
            label: const Text('سجل النقاط'),
            backgroundColor: AppColors.accentBlue,
          ),
          const SizedBox(width: 12),
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
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: rank <= 3 ? AppColors.accentOrange : Colors.grey.shade300,
                      child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    title: Text(r['studentName'] ?? ''),
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
