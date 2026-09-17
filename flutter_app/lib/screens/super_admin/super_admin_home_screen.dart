import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../utils/json_utils.dart';

/// يقابل لوحة السوبر أدمن (superAdminGetOverview) في main.html القديم —
/// بما فيها عمودي "آخر نشاط" و"نسبة الحضور" المضافين في آخر تحديث.
class SuperAdminHomeScreen extends StatefulWidget {
  const SuperAdminHomeScreen({super.key});

  @override
  State<SuperAdminHomeScreen> createState() => _SuperAdminHomeScreenState();
}

class _SuperAdminHomeScreenState extends State<SuperAdminHomeScreen> {
  late Future<Map<String, dynamic>> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _overviewFuture = context.read<ApiService>().superAdminGetOverview();
  }

  Future<void> _showCreateCircleDialog() async {
    final circleNameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String? dialogError;
    bool submitting = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
            builder: (context, setInner) {
              return AlertDialog(
                title: const Text('إنشاء مجمع جديد'),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: circleNameCtrl,
                        decoration: const InputDecoration(labelText: 'اسم المجمع'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: usernameCtrl,
                        decoration: const InputDecoration(labelText: 'اسم مستخدم صاحب المجمع'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'كلمة المرور'),
                        validator: (v) => (v == null || v.length < 4) ? '4 أحرف على الأقل' : null,
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(dialogError!, style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                  ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setInner(() {
                              submitting = true;
                              dialogError = null;
                            });
                            try {
                              await context.read<ApiService>().superAdminCreateCircle(
                                    circleName: circleNameCtrl.text.trim(),
                                    ownerUsername: usernameCtrl.text.trim(),
                                    password: passwordCtrl.text,
                                  );
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (e) {
                              setInner(() {
                                submitting = false;
                                dialogError = 'فشل الإنشاء: $e';
                              });
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('إنشاء'),
                  ),
                ],
              );
            },
          ),
    );

    if (created == true) setState(_load);
  }

  Future<void> _showEditCircleDialog(Map<String, dynamic> circle) async {
    final nameCtrl = TextEditingController(text: (circle['circleName'] ?? '').toString());
    DateTime? startDate = _parseDate(circle['startDate']);
    DateTime? endDate = _parseDate(circle['endDate']);
    String? dialogError;
    bool submitting = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
            builder: (context, setInner) {
              return AlertDialog(
                title: const Text('تعديل المجمع'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'اسم المجمع'),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(startDate == null
                            ? 'تاريخ البداية: غير محدد'
                            : 'تاريخ البداية: ${_fmtDate(startDate!)}'),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setInner(() => startDate = picked);
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(endDate == null
                            ? 'تاريخ النهاية: غير محدد'
                            : 'تاريخ النهاية: ${_fmtDate(endDate!)}'),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setInner(() => endDate = picked);
                        },
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(dialogError!, style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                  ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            setInner(() {
                              submitting = true;
                              dialogError = null;
                            });
                            try {
                              await context.read<ApiService>().superAdminUpdateCircle(
                                    circleId: circle['circleId'].toString(),
                                    updates: {
                                      'circleName': nameCtrl.text.trim(),
                                      'startDate': startDate == null ? null : _fmtDate(startDate!),
                                      'endDate': endDate == null ? null : _fmtDate(endDate!),
                                    },
                                  );
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (e) {
                              setInner(() {
                                submitting = false;
                                dialogError = 'فشل الحفظ: $e';
                              });
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
    );

    if (saved == true) setState(_load);
  }

  Future<void> _confirmDeleteCircle(Map<String, dynamic> circle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المجمع'),
        content:
            Text('هل أنت متأكد من حذف "${circle['circleName']}"؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context.read<ApiService>().superAdminDeleteCircle(circleId: circle['circleId'].toString());
      if (mounted) setState(_load);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
      }
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة السوبر أدمن'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCircleDialog,
        icon: const Icon(Icons.add),
        label: const Text('مجمع جديد'),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: FutureBuilder<Map<String, dynamic>>(
                future: _overviewFuture,
                builder: (context, snapshot) {
                  try {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('يتم التحميل...'),
                            ],
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              'حدث خطأ أثناء تحميل البيانات: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const Center(child: Text('لا توجد بيانات متاحة حاليًا.'));
                    }
                    final data = snapshot.data!;
                    List<Map<String, dynamic>> circles;
                    try {
                      circles = asMapList(data['circles']);
                    } catch (e, st) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              'تعذّر تحويل بيانات المجمعات: $e',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            _StatCard(label: 'المجمعات', value: '${data['circlesCount']}'),
                            const SizedBox(width: 12),
                            _StatCard(label: 'المعلمون', value: '${data['teachersCount']}'),
                            const SizedBox(width: 12),
                            _StatCard(label: 'الطلاب', value: '${data['studentsCount']}'),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ...circles.map((c) => Card(
                              child: ListTile(
                                title: Text(c['circleName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  'معلمون: ${c['teachersCount']} · طلاب: ${c['studentsCount']} · '
                                  'آخر نشاط: ${c['lastActivity'] ?? '-'} · '
                                  'نسبة الحضور: ${c['attendanceRate'] != null ? '${c['attendanceRate']}%' : '-'} · '
                          'من ${c['startDate'] ?? '-'} إلى ${c['endDate'] ?? '-'}',
                                ),
                                trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: 'تعديل',
                                onPressed: () => _showEditCircleDialog(c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                tooltip: 'حذف',
                                onPressed: () => _confirmDeleteCircle(c),
                              ),
                            ],
                          ),
                          leading: const CircleAvatar(
                                  backgroundColor: AppColors.primary,
                                  child: Icon(Icons.groups, color: Colors.white),
                                ),
                              ),
                            )),
                      ],
                    );
                  } catch (e, st) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            'حدث خطأ غير متوقع أثناء عرض الشاشة: $e',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
