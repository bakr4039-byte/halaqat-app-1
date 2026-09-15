import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

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
                              // ignore: avoid_print
                              print('CREATE CIRCLE DEBUG ERROR: $e');
                              setInner(() {
                                submitting = false;
                                dialogError = 'فشل الإنشاء (تشخيص مؤقت): $e';
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
      body: RefreshIndicator(
        onRefresh: () async => setState(_load),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _overviewFuture,
          builder: (context, snapshot) {
            // ignore: avoid_print
            print('OVERVIEW DEBUG: state=${snapshot.connectionState} '
                'hasError=${snapshot.hasError} error=${snapshot.error} '
                'hasData=${snapshot.hasData} data=${snapshot.data}');
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('جارِ التحميل (تشخيص مؤقت)...'),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('خطأ (تشخيص مؤقت): ${snapshot.error}\n\n${snapshot.stackTrace}'),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return const Center(child: Text('لا توجد بيانات (تشخيص مؤقت): hasData=false'));
            }
            final data = snapshot.data!;
            List<Map<String, dynamic>> circles;
            try {
              circles = (data['circles'] as List).cast<Map<String, dynamic>>();
            } catch (e, st) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('خطأ تحويل البيانات (تشخيص مؤقت): $e\n\nالبيانات الخام: $data\n\n$st'),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('تشخيص مؤقت: عدد المجمعات المستلمة = ${circles.length}',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
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
                          'نسبة الحضور: ${c['attendanceRate'] != null ? '${c['attendanceRate']}%' : '-'}',
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.primary,
                          child: Icon(Icons.groups, color: Colors.white),
                        ),
                      ),
                    )),
              ],
            );
          },
        ),
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
