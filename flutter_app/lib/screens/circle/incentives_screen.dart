import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';

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
          (res) => (res['leaderboard'] as List).cast<Map<String, dynamic>>(),
        );
  }

  Future<void> _showApplyPointsDialog() async {
    final api = context.read<ApiService>();
    final itemsRes = await api.getIncentiveItems(widget.circleId);
    final studentsRes = await api.getStudents(widget.circleId);
    final items = (itemsRes['items'] as List).cast<Map<String, dynamic>>();
    final students = (studentsRes['students'] as List).cast<Map<String, dynamic>>();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showApplyPointsDialog,
        icon: const Icon(Icons.add_reaction_outlined),
        label: const Text('تطبيق نقاط'),
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
