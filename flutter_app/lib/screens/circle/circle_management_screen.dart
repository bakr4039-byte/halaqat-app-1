import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/json_utils.dart';

/// شاشة إدارة المجمع لصاحب المجمع — نسخة كاملة تقابل قسم "إدارة الطلاب" في
/// التطبيق القديم (main.html): إعدادات المجمع، المعلمون، الطلاب، اللجنة
/// التحفيزية، والتقارير — كل ذلك في مكان واحد بدل ما صاحب المجمع يفتح على
/// شاشة تسجيل حضوره الشخصي فقط.
class CircleManagementScreen extends StatefulWidget {
  final String circleId;
  const CircleManagementScreen({super.key, required this.circleId});

  @override
  State<CircleManagementScreen> createState() => _CircleManagementScreenState();
}

class _CircleManagementScreenState extends State<CircleManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'الإعدادات والمعلمون'),
              Tab(text: 'الطلاب'),
              Tab(text: 'التحفيز'),
              Tab(text: 'التقارير'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _SettingsAndTeachersTab(circleId: widget.circleId),
              _StudentsTab(circleId: widget.circleId),
              _IncentivesManagementTab(circleId: widget.circleId),
              _ReportsTab(circleId: widget.circleId),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// التاب الأول: إعدادات المجمع + إدارة المعلمين
// (getInitialData + saveTeachersAndSettings)
// ============================================================
class _SettingsAndTeachersTab extends StatefulWidget {
  final String circleId;
  const _SettingsAndTeachersTab({required this.circleId});

  @override
  State<_SettingsAndTeachersTab> createState() => _SettingsAndTeachersTabState();
}

class _SettingsAndTeachersTabState extends State<_SettingsAndTeachersTab> {
  late Future<Map<String, dynamic>> _initialFuture;
  bool _saving = false;
  String? _saveError;
  String? _saveSuccess;
  bool _loaded = false;
  int _keyCounter = 0;

  final _circlePhoneCtrl = TextEditingController();
  final _prayerCityCtrl = TextEditingController();
  final _workDaysCtrl = TextEditingController();
  final _shiftDurationCtrl = TextEditingController();
  final _graceMinutesCtrl = TextEditingController();
  final _reminderMinutesCtrl = TextEditingController();
  final _reportEmailCtrl = TextEditingController();
  String _prayerSlot = 'Asr';
  bool _autoWhatsapp = false;
  bool _prayerReminderEnabled = true;
  bool _teacherReminderEnabled = false;

  List<Map<String, dynamic>> _teachers = [];

  static const _prayerSlots = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
  static const _prayerSlotLabels = {
    'Fajr': 'الفجر',
    'Dhuhr': 'الظهر',
    'Asr': 'العصر',
    'Maghrib': 'المغرب',
    'Isha': 'العشاء',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _newKey() => 'new_${_keyCounter++}';

  void _load() {
    _initialFuture = context.read<ApiService>().getInitialData(widget.circleId).then((res) {
      if (!_loaded) {
        final settings = Map<String, dynamic>.from(res['settings'] as Map? ?? {});
        final teachers = asMapList(res['teachers']);

        _circlePhoneCtrl.text = settings['circlePhone']?.toString() ?? '';
        _prayerCityCtrl.text = settings['prayerCity']?.toString() ?? '';
        _workDaysCtrl.text = (settings['workDays'] ?? 5).toString();
        _shiftDurationCtrl.text = (settings['shiftDurationMins'] ?? 120).toString();
        _graceMinutesCtrl.text = (settings['graceMinutes'] ?? 0).toString();
        _reminderMinutesCtrl.text = (settings['reminderMinutesBefore'] ?? 15).toString();
        _reportEmailCtrl.text = settings['reportEmail']?.toString() ?? '';
        _prayerSlot = _prayerSlots.contains(settings['prayerSlot']) ? settings['prayerSlot'] as String : 'Asr';
        _autoWhatsapp = settings['autoWhatsapp'] == true;
        _prayerReminderEnabled = settings['prayerReminderEnabled'] != false;
        _teacherReminderEnabled = settings['teacherReminderEnabled'] == true;
        _teachers = teachers.map((t) => {...t, '_key': (t['id'] ?? _newKey()).toString()}).toList();
        _loaded = true;
      }
      return res;
    });
  }

  @override
  void dispose() {
    _circlePhoneCtrl.dispose();
    _prayerCityCtrl.dispose();
    _workDaysCtrl.dispose();
    _shiftDurationCtrl.dispose();
    _graceMinutesCtrl.dispose();
    _reminderMinutesCtrl.dispose();
    _reportEmailCtrl.dispose();
    super.dispose();
  }

  void _addTeacher() {
    setState(() {
      _teachers.add({
        'name': '',
        'phone': '',
        'salary': 0,
        'bonus': 0,
        'subCircle': '',
        'username': '',
        '_key': _newKey(),
      });
    });
  }

  void _removeTeacher(int index) {
    setState(() => _teachers.removeAt(index));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
      _saveSuccess = null;
    });
    try {
      final settings = {
        'circlePhone': _circlePhoneCtrl.text.trim(),
        'prayerCity': _prayerCityCtrl.text.trim(),
        'workDays': int.tryParse(_workDaysCtrl.text) ?? 5,
        'prayerSlot': _prayerSlot,
        'shiftDurationMins': int.tryParse(_shiftDurationCtrl.text) ?? 120,
        'graceMinutes': int.tryParse(_graceMinutesCtrl.text) ?? 0,
        'reminderMinutesBefore': int.tryParse(_reminderMinutesCtrl.text) ?? 15,
        'reportEmail': _reportEmailCtrl.text.trim(),
        'autoWhatsapp': _autoWhatsapp,
        'prayerReminderEnabled': _prayerReminderEnabled,
        'teacherReminderEnabled': _teacherReminderEnabled,
      };

      final teachersToSend = _teachers.map((t) {
        final m = Map<String, dynamic>.from(t);
        m.remove('_key');
        return m;
      }).toList();

      await context.read<ApiService>().saveTeachersAndSettings(
            circleId: widget.circleId,
            teachers: teachersToSend,
            settings: settings,
          );

      if (mounted) setState(() => _saveSuccess = 'تم الحفظ بنجاح.');
    } catch (e) {
      if (mounted) setState(() => _saveError = 'فشل الحفظ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _loaded = false;
        setState(_load);
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _initialFuture,
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('إعدادات المجمع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _circlePhoneCtrl,
                decoration: const InputDecoration(labelText: 'رقم هاتف المجمع'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prayerCityCtrl,
                decoration: const InputDecoration(labelText: 'مدينة مواقيت الصلاة'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _prayerSlot,
                decoration: const InputDecoration(labelText: 'وقت الحلقة (الصلاة)'),
                items: _prayerSlots
                    .map((s) => DropdownMenuItem(value: s, child: Text(_prayerSlotLabels[s] ?? s)))
                    .toList(),
                onChanged: (v) => setState(() => _prayerSlot = v ?? _prayerSlot),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _workDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'أيام العمل بالأسبوع'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _shiftDurationCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'مدة الحلقة (دقيقة)'),

                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _graceMinutesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'مهلة السماح (دقيقة)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _reminderMinutesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'تذكير قبل الحلقة بـ (دقيقة)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reportEmailCtrl,
                decoration: const InputDecoration(labelText: 'بريد إرسال التقارير'),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إرسال واتساب تلقائي'),
                value: _autoWhatsapp,
                onChanged: (v) => setState(() => _autoWhatsapp = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تذكير قبل الحلقة'),
                value: _prayerReminderEnabled,
                onChanged: (v) => setState(() => _prayerReminderEnabled = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تذكير المعلمين'),
                value: _teacherReminderEnabled,
                onChanged: (v) => setState(() => _teacherReminderEnabled = v),
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('المعلمون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _addTeacher,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة معلم'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_teachers.isEmpty) const Text('لا يوجد معلمون بعد. أضف معلمًا للبدء.'),
              ..._teachers.asMap().entries.map((entry) {
                final i = entry.key;
                final t = entry.value;
                return Card(
                  key: ValueKey(t['_key']),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: t['name']?.toString() ?? '',
                                decoration: const InputDecoration(labelText: 'اسم المعلم'),
                                onChanged: (v) => t['name'] = v,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                              onPressed: () => _removeTeacher(i),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: t['username']?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'اسم المستخدم (لتسجيل الدخول)'),
                          onChanged: (v) => t['username'] = v,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: t['id'] == null ? 'كلمة المرور (مطلوبة لإنشاء حساب المعلم)' : 'كلمة مرور جديدة (اتركها فاضية للإبقاء عليها)',
                          ),
                          onChanged: (v) => t['password'] = v,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: t['phone']?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                          onChanged: (v) => t['phone'] = v,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: t['salary']?.toString() ?? '0',
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'الراتب'),
                                onChanged: (v) => t['salary'] = num.tryParse(v) ?? 0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: t['bonus']?.toString() ?? '0',
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'المكافأة'),
                                onChanged: (v) => t['bonus'] = num.tryParse(v) ?? 0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: t['subCircle']?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'المجموعة الفرعية (اختياري)'),
                          onChanged: (v) => t['subCircle'] = v,
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
              if (_saveError != null) ...[
                Text(_saveError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_saveSuccess != null) ...[
                Text(_saveSuccess!, style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 8),
              ],
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: const Text('حفظ التغييرات'),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// التاب الثاني: إدارة الطلاب (إضافة/تعديل/حذف)
// (getStudents + saveStudents + قائمة المعلمين من getInitialData)
// ============================================================
class _StudentsTab extends StatefulWidget {
  final String circleId;
  const _StudentsTab({required this.circleId});

  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> {
  late Future<void> _loadFuture;
  bool _loaded = false;
  bool _saving = false;
  String? _saveError;
  String? _saveSuccess;
  int _keyCounter = 0;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _teachers = [];

  static const _statusLabels = {'active': 'نشط', 'inactive': 'غير نشط'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _newKey() => 'new_${_keyCounter++}';

  void _load() {
    final api = context.read<ApiService>();
    _loadFuture = Future.wait([
      api.getStudents(widget.circleId),
      api.getInitialData(widget.circleId),
    ]).then((results) {
      final studentsRes = results[0];
      final initialRes = results[1];
      _students = asMapList(studentsRes['students'])
          .map((s) => {...s, '_key': (s['id'] ?? _newKey()).toString()})
          .toList();
      _teachers = asMapList(initialRes['teachers']);
      _loaded = true;
    });
  }

  void _addStudent() {
    setState(() {
      _students.add({
        'name': '',
        'guardianName': '',
        'guardianPhone': '',
        'stage': '',
        'teacherId': '',
        'subCircle': '',
        'address': '',
        'notes': '',
        'status': 'active',
        '_key': _newKey(),
      });
    });
  }

  void _removeStudent(int index) {
    setState(() => _students.removeAt(index));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
      _saveSuccess = null;
    });
    try {
      final studentsToSend = _students.map((s) {
        final m = Map<String, dynamic>.from(s);
        m.remove('_key');
        return m;
      }).toList();

      await context.read<ApiService>().saveStudents(circleId: widget.circleId, students: studentsToSend);
      if (mounted) setState(() => _saveSuccess = 'تم حفظ بيانات الطلاب بنجاح.');
    } catch (e) {
      if (mounted) setState(() => _saveError = 'فشل الحفظ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('قائمة الطلاب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _addStudent,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة طالب'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_students.isEmpty) const Text('لا يوجد طلاب بعد. أضف طالبًا للبدء.'),
              ..._students.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                final currentTeacherId = (s['teacherId']?.toString().isEmpty ?? true) ? null : s['teacherId'].toString();
                final teacherExists = currentTeacherId == null ||
                    _teachers.any((t) => t['id']?.toString() == currentTeacherId);
                return Card(
                  key: ValueKey(s['_key']),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: s['name']?.toString() ?? '',
                                decoration: const InputDecoration(labelText: 'اسم الطالب'),
                                onChanged: (v) => s['name'] = v,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                              onPressed: () => _removeStudent(i),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: s['guardianName']?.toString() ?? '',
                                decoration: const InputDecoration(labelText: 'ولي الأمر'),
                                onChanged: (v) => s['guardianName'] = v,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: s['guardianPhone']?.toString() ?? '',
                                decoration: const InputDecoration(labelText: 'جوال ولي الأمر'),
                                onChanged: (v) => s['guardianPhone'] = v,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: teacherExists ? currentTeacherId : null,
                          decoration: const InputDecoration(labelText: 'المعلم'),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('بدون معلم محدد')),
                            ..._teachers.map((t) => DropdownMenuItem<String>(
                                  value: t['id']?.toString(),
                                  child: Text(t['name']?.toString() ?? ''),
                                )),
                          ],
                          onChanged: (v) => s['teacherId'] = v ?? '',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: s['stage']?.toString() ?? '',
                                decoration: const InputDecoration(labelText: 'المرحلة'),
                                onChanged: (v) => s['stage'] = v,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: s['subCircle']?.toString() ?? '',
                                decoration: const InputDecoration(labelText: 'الحلقة الفرعية'),
                                onChanged: (v) => s['subCircle'] = v,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: s['address']?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'العنوان'),
                          onChanged: (v) => s['address'] = v,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: s['notes']?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'ملاحظات'),
                          onChanged: (v) => s['notes'] = v,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _statusLabels.containsKey(s['status']) ? s['status'] as String : 'active',
                          decoration: const InputDecoration(labelText: 'الحالة'),
                          items: _statusLabels.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => s['status'] = v ?? 'active',
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
              if (_saveError != null) ...[
                Text(_saveError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_saveSuccess != null) ...[
                Text(_saveSuccess!, style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 8),
              ],
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: const Text('حفظ التغييرات'),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// التاب الثالث: إدارة اللجنة التحفيزية (بنود المنح/الخصم + سجل العمليات)
// (getIncentiveItems + saveIncentiveItem + deleteIncentiveItem + getIncentiveLedger)
// ============================================================
class _IncentivesManagementTab extends StatefulWidget {
  final String circleId;
  const _IncentivesManagementTab({required this.circleId});

  @override
  State<_IncentivesManagementTab> createState() => _IncentivesManagementTabState();
}

class _IncentivesManagementTabState extends State<_IncentivesManagementTab> {
  late Future<void> _loadFuture;
  bool _loaded = false;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _ledger = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<ApiService>();
    _loadFuture = Future.wait([
      api.getIncentiveItems(widget.circleId),
      api.getIncentiveLedger(widget.circleId),
    ]).then((results) {
      _items = asMapList(results[0]['items']);
      _ledger = asMapList(results[1]['ledger']);
      _loaded = true;
    });
  }

  Future<void> _showItemDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final pointsCtrl = TextEditingController(text: existing?['points']?.toString() ?? '1');
    String type = existing?['type']?.toString() ?? 'grant';
    final formKey = GlobalKey<FormState>();
    String? dialogError;
    bool submitting = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(existing == null ? 'إضافة بند تحفيزي' : 'تعديل البند'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم البند'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'النوع'),
                  items: const [
                    DropdownMenuItem(value: 'grant', child: Text('منح (+)')),
                    DropdownMenuItem(value: 'deduct', child: Text('خصم (-)')),
                  ],
                  onChanged: (v) => setInner(() => type = v ?? 'grant'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: pointsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'عدد النقاط'),
                  validator: (v) => (num.tryParse(v ?? '') == null) ? 'رقم غير صحيح' : null,
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
                        await context.read<ApiService>().saveIncentiveItem(
                              circleId: widget.circleId,
                              item: {
                                if (existing?['id'] != null) 'id': existing!['id'],
                                'name': nameCtrl.text.trim(),
                                'type': type,
                                'points': num.tryParse(pointsCtrl.text) ?? 0,
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
        ),
      ),
    );

    if (saved == true && mounted) setState(_load);
  }

  Future<void> _deleteItem(String itemId) async {
    try {
      await context.read<ApiService>().deleteIncentiveItem(circleId: widget.circleId, itemId: itemId);
      if (mounted) setState(_load);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
      }
    }
  }

  Future<void> _deleteLedgerEntry(String transactionId) async {
    try {
      await context.read<ApiService>().deleteIncentiveTransaction(
            circleId: widget.circleId,
            transactionId: transactionId,
          );
      if (mounted) setState(_load);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
      }
    }
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('بنود المنح والخصم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () => _showItemDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة بند'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_items.isEmpty) const Text('لا توجد بنود بعد.'),
              ..._items.map((it) {
                final isGrant = it['type'] == 'grant';
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isGrant ? AppColors.primary : AppColors.danger,
                      child: Icon(isGrant ? Icons.add : Icons.remove, color: Colors.white),
                    ),
                    title: Text(it['name']?.toString() ?? ''),
                    subtitle: Text('${isGrant ? '+' : '-'}${it['points']} نقطة'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showItemDialog(existing: it),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () => _deleteItem(it['id'].toString()),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const Divider(height: 32),
              const Text('سجل آخر العمليات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_ledger.isEmpty) const Text('لا توجد عمليات مسجّلة بعد.'),
              ..._ledger.take(50).map((entry) {
                final isGrant = entry['type'] == 'grant';
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(entry['studentName']?.toString() ?? ''),
                    subtitle: Text('${entry['itemName'] ?? ''} · ${isGrant ? '+' : '-'}${entry['points']} نقطة'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () => _deleteLedgerEntry(entry['id'].toString()),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// التاب الرابع: تقرير حضور الطلاب
// (getStudentAttendanceReport بفترة زمنية محددة)
// ============================================================
class _ReportsTab extends StatefulWidget {
  final String circleId;
  const _ReportsTab({required this.circleId});

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _toDate = DateTime.now();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _records = [];
  bool _searched = false;

  String _fmt(DateTime d) => intl.DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _runReport() async {
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final res = await context.read<ApiService>().getStudentAttendanceReport(
            circleId: widget.circleId,
            fromDateKey: _fmt(_fromDate),
            toDateKey: _fmt(_toDate),
          );
      final records = asMapList(res['records']);
      records.sort((a, b) => (b['dateKey']?.toString() ?? '').compareTo(a['dateKey']?.toString() ?? ''));
      if (mounted) setState(() => _records = records);
    } catch (e) {
      if (mounted) setState(() => _error = 'فشل عرض التقرير: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _records.where((r) => r['status'] == 'present').length;
    final absentCount = _records.where((r) => r['status'] == 'absent').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('تقرير حضور الطلاب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(isFrom: true),
                child: Text('من: ${_fmt(_fromDate)}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(isFrom: false),
                child: Text('إلى: ${_fmt(_toDate)}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _loading ? null : _runReport,
          icon: _loading
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search),
          label: const Text('عرض التقرير'),
        ),
        const SizedBox(height: 20),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_searched && !_loading && _error == null) ...[
          Row(
            children: [
              Expanded(child: _ReportStatCard(label: 'حاضر', value: '$presentCount', color: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: _ReportStatCard(label: 'غائب', value: '$absentCount', color: AppColors.danger)),
            ],
          ),
          const SizedBox(height: 16),
          if (_records.isEmpty) const Text('لا توجد سجلات في هذه الفترة.'),
          ..._records.map((r) {
            final isPresent = r['status'] == 'present';
            return Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                  isPresent ? Icons.check_circle : Icons.cancel,
                  color: isPresent ? AppColors.primary : AppColors.danger,
                ),
                title: Text(r['studentName']?.toString() ?? ''),
                subtitle: Text(r['dateKey']?.toString() ?? ''),
              ),
            );
          }),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ReportStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ReportStatCard({required this.label, required this.value, required this.color});

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

