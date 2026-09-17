import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/export_utils.dart';
import '../../utils/json_utils.dart';
import 'payroll_export_tab.dart';
import 'teacher_dashboard_tab.dart';

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
    _tabController = TabController(length: 6, vsync: this);
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
              Tab(text: 'الرئيسية'),
              Tab(text: 'الإعدادات والمعلمون'),
              Tab(text: 'الإحصائيات والرواتب'),
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
              TeacherDashboardTab(circleId: widget.circleId),
              _SettingsAndTeachersTab(circleId: widget.circleId),
              PayrollExportTab(circleId: widget.circleId),
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
  final _logoUrlCtrl = TextEditingController();
  final _targetCheckInCtrl = TextEditingController();
  final _targetCheckOutCtrl = TextEditingController();
  final _autoAbsentCutoffCtrl = TextEditingController();
  final _circleLatCtrl = TextEditingController();
  final _circleLngCtrl = TextEditingController();
  final _geofenceRadiusCtrl = TextEditingController();
  final _googleSheetIdCtrl = TextEditingController();
  String _prayerSlot = 'Asr';
  bool _autoWhatsapp = false;
  bool _prayerReminderEnabled = true;
  bool _teacherReminderEnabled = false;
  bool _geofenceEnabled = false;
  bool _autoAbsentEnabled = false;
  bool _locatingNow = false;
  String _calendarType = 'gregorian';
  Color _themeColor = AppColors.primary;

  static const _themeColorOptions = <Color>[
    AppColors.primary,
    AppColors.accentBlue,
    AppColors.accentOrange,
    AppColors.danger,
    Colors.teal,
    Colors.indigo,
  ];

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
        _logoUrlCtrl.text = settings['logoUrl']?.toString() ?? '';
        _targetCheckInCtrl.text = settings['targetCheckInTime']?.toString() ?? '';
        _targetCheckOutCtrl.text = settings['targetCheckOutTime']?.toString() ?? '';
        _autoAbsentCutoffCtrl.text = settings['autoAbsentCutoffTime']?.toString() ?? '';
        _circleLatCtrl.text = settings['circleLat']?.toString() ?? '';
        _circleLngCtrl.text = settings['circleLng']?.toString() ?? '';
        _geofenceRadiusCtrl.text = settings['geofenceRadiusMeters']?.toString() ?? '100';
        _googleSheetIdCtrl.text = settings['googleSheetId']?.toString() ?? '';
        _prayerSlot = _prayerSlots.contains(settings['prayerSlot']) ? settings['prayerSlot'] as String : 'Asr';
        _autoWhatsapp = settings['autoWhatsapp'] == true;
        _prayerReminderEnabled = settings['prayerReminderEnabled'] != false;
        _teacherReminderEnabled = settings['teacherReminderEnabled'] == true;
        _geofenceEnabled = settings['geofenceEnabled'] == true;
        _autoAbsentEnabled = settings['autoAbsentEnabled'] == true;
        _calendarType = settings['calendarType'] == 'hijri' ? 'hijri' : 'gregorian';
        final themeHex = settings['themeColor']?.toString();
        if (themeHex != null && themeHex.startsWith('#')) {
          final parsed = int.tryParse(themeHex.substring(1), radix: 16);
          if (parsed != null) _themeColor = Color(0xFF000000 | parsed);
        }
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
    _logoUrlCtrl.dispose();
    _targetCheckInCtrl.dispose();
    _targetCheckOutCtrl.dispose();
    _autoAbsentCutoffCtrl.dispose();
    _circleLatCtrl.dispose();
    _circleLngCtrl.dispose();
    _geofenceRadiusCtrl.dispose();
    _googleSheetIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locatingNow = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'خدمة الموقع غير مفعّلة على الجهاز.';
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw 'صلاحية الموقع مرفوضة.';
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() {
        _circleLatCtrl.text = pos.latitude.toStringAsFixed(6);
        _circleLngCtrl.text = pos.longitude.toStringAsFixed(6);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر تحديد الموقع: $e')));
    } finally {
      if (mounted) setState(() => _locatingNow = false);
    }
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
        'logoUrl': _logoUrlCtrl.text.trim(),
        'targetCheckInTime': _targetCheckInCtrl.text.trim(),
        'targetCheckOutTime': _targetCheckOutCtrl.text.trim(),
        'autoAbsentEnabled': _autoAbsentEnabled,
        'autoAbsentCutoffTime': _autoAbsentCutoffCtrl.text.trim(),
        'geofenceEnabled': _geofenceEnabled,
        'circleLat': double.tryParse(_circleLatCtrl.text.trim()),
        'circleLng': double.tryParse(_circleLngCtrl.text.trim()),
        'geofenceRadiusMeters': int.tryParse(_geofenceRadiusCtrl.text.trim()) ?? 100,
        'googleSheetId': _googleSheetIdCtrl.text.trim(),
        'calendarType': _calendarType,
        'themeColor': '#${_themeColor.value.toRadixString(16).substring(2)}',
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تسجيل غياب تلقائي'),
                subtitle: const Text('لأي معلم لم يسجل حضوره حتى الساعة المحددة — تعمل من الخادم حتى لو التطبيق مغلق'),
                value: _autoAbsentEnabled,
                onChanged: (v) => setState(() => _autoAbsentEnabled = v),
              ),
              if (_autoAbsentEnabled)
                TextField(
                  controller: _autoAbsentCutoffCtrl,
                  decoration: const InputDecoration(labelText: 'ساعة تسجيل الغياب التلقائي (HH:mm)', hintText: '14:00'),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetCheckInCtrl,
                      decoration: const InputDecoration(labelText: 'وقت الحضور المستهدف (HH:mm)', hintText: '15:30'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _targetCheckOutCtrl,
                      decoration: const InputDecoration(labelText: 'وقت الانصراف المستهدف (HH:mm)', hintText: '17:00'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('تنسيق التقويم', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gregorian', label: Text('ميلادي')),
                  ButtonSegment(value: 'hijri', label: Text('هجري')),
                ],
                selected: {_calendarType},
                onSelectionChanged: (s) => setState(() => _calendarType = s.first),
              ),
              const SizedBox(height: 16),
              const Text('تنسيق الألوان', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: _themeColorOptions.map((c) {
                  final selected = c.value == _themeColor.value;
                  return GestureDetector(
                    onTap: () => setState(() => _themeColor = c),
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: selected ? 18 : 14,
                      child: selected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _logoUrlCtrl,
                decoration: const InputDecoration(labelText: 'رابط شعار المجمع (Logo URL)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _googleSheetIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'معرّف Google Sheet (لحفظ تسجيل اليوم)',
                  hintText: 'يُنسخ من رابط جدول البيانات',
                ),
              ),
              const Divider(height: 32),
              const Text('نقطة الموقع الجغرافي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'السماح بتسجيل الحضور/الانصراف فقط داخل موقع العمل، بتحديد خط الطول والعرض ونطاق المسافة بالمتر.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('السماح بتسجيل الحضور/الانصراف داخل موقع العمل فقط'),
                value: _geofenceEnabled,
                onChanged: (v) => setState(() => _geofenceEnabled = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _circleLatCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'خط العرض (Latitude)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _circleLngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'خط الطول (Longitude)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _geofenceRadiusCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'نطاق المسافة المسموح به (متر)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _locatingNow ? null : _useCurrentLocation,
                icon: _locatingNow
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
                label: const Text('استخدام موقعي الحالي كموقع المجمع'),
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

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _filterTeacherId;
  String? _filterSubCircle;
  String? _filterStatus;
  bool _importing = false;

  static const _statusLabels = {'active': 'نشط', 'inactive': 'غير نشط'};

  List<Map<String, dynamic>> get _filteredStudents {
    return _students.where((s) {
      if (_searchQuery.isNotEmpty && !(s['name']?.toString() ?? '').contains(_searchQuery)) return false;
      if (_filterTeacherId != null && s['teacherId']?.toString() != _filterTeacherId) return false;
      if (_filterSubCircle != null && (s['subCircle']?.toString() ?? '') != _filterSubCircle) return false;
      if (_filterStatus != null && (s['status']?.toString() ?? 'active') != _filterStatus) return false;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _newKey() => 'new_${_keyCounter++}';

  String _teacherName(String? id) {
    if (id == null || id.isEmpty) return '';
    final match = _teachers.where((t) => t['id']?.toString() == id).toList();
    return match.isNotEmpty ? (match.first['name']?.toString() ?? '') : '';
  }

  List<List<String>> _exportRows(List<Map<String, dynamic>> list) => list
      .map((s) => [
            s['name']?.toString() ?? '',
            s['guardianName']?.toString() ?? '',
            s['guardianPhone']?.toString() ?? '',
            s['stage']?.toString() ?? '',
            _teacherName(s['teacherId']?.toString()),
            s['subCircle']?.toString() ?? '',
            s['address']?.toString() ?? '',
            _statusLabels[s['status']?.toString()] ?? 'نشط',
          ])
      .toList();

  static const _exportHeaders = ['اسم الطالب', 'ولي الأمر', 'جوال ولي الأمر', 'المرحلة', 'المعلم', 'الحلقة', 'العنوان', 'الحالة'];

  Future<void> _exportPdf() async {
    await exportTablePdf(title: 'قائمة الطلاب', headers: _exportHeaders, rows: _exportRows(_filteredStudents), fileName: 'قائمة_الطلاب.pdf');
  }

  Future<void> _exportExcel() async {
    await exportTableExcel(sheetTitle: 'الطلاب', headers: _exportHeaders, rows: _exportRows(_filteredStudents), fileName: 'قائمة_الطلاب.xlsx');
  }

  /// استيراد من إكسل — يتوقع الأعمدة بنفس ترتيب التصدير: اسم الطالب، ولي
  /// الأمر، جوال ولي الأمر، المرحلة، المعلم (بالاسم)، الحلقة، العنوان، الحالة.
  /// الصف الأول يُعتبر رؤوس أعمدة ويُتجاهل.
  Future<void> _importExcel() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;

      final rows = readExcelRows(Uint8List.fromList(bytes));
      if (rows.isEmpty) return;

      var imported = 0;
      for (final row in rows.skip(1)) {
        if (row.isEmpty || row[0].trim().isEmpty) continue;
        final teacherMatch = row.length > 4
            ? _teachers.where((t) => (t['name']?.toString() ?? '') == row[4].trim()).toList()
            : <Map<String, dynamic>>[];
        _students.add({
          'name': row[0].trim(),
          'guardianName': row.length > 1 ? row[1].trim() : '',
          'guardianPhone': row.length > 2 ? row[2].trim() : '',
          'stage': row.length > 3 ? row[3].trim() : '',
          'teacherId': teacherMatch.isNotEmpty ? teacherMatch.first['id'].toString() : '',
          'subCircle': row.length > 5 ? row[5].trim() : '',
          'address': row.length > 6 ? row[6].trim() : '',
          'notes': '',
          'status': (row.length > 7 && row[7].trim() == 'غير نشط') ? 'inactive' : 'active',
          '_key': _newKey(),
        });
        imported++;
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم استيراد $imported طالب. راجع البيانات ثم اضغط "حفظ التغييرات".')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

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

  void _removeStudent(String key) {
    setState(() => _students.removeWhere((s) => s['_key'] == key));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

          final subCircles = _students.map((s) => s['subCircle']?.toString() ?? '').where((v) => v.isNotEmpty).toSet().toList();
          final filtered = _filteredStudents;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('قائمة الطلاب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Wrap(spacing: 4, children: [
                    IconButton(
                      tooltip: 'استيراد من إكسل',
                      onPressed: _importing ? null : _importExcel,
                      icon: _importing
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file_outlined),
                    ),
                    IconButton(tooltip: 'تصدير PDF', onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
                    IconButton(tooltip: 'تصدير Excel', onPressed: _exportExcel, icon: const Icon(Icons.grid_on_outlined)),
                    TextButton.icon(
                      onPressed: _addStudent,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة طالب'),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(labelText: 'بحث باسم الطالب', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DropdownButton<String?>(
                    value: _filterTeacherId,
                    hint: const Text('المعلم'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('كل المعلمين')),
                      ..._teachers.map((t) => DropdownMenuItem<String?>(value: t['id']?.toString(), child: Text(t['name']?.toString() ?? ''))),
                    ],
                    onChanged: (v) => setState(() => _filterTeacherId = v),
                  ),
                  DropdownButton<String?>(
                    value: _filterSubCircle,
                    hint: const Text('الحلقة الفرعية'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('كل الحلقات')),
                      ...subCircles.map((sc) => DropdownMenuItem<String?>(value: sc, child: Text(sc))),
                    ],
                    onChanged: (v) => setState(() => _filterSubCircle = v),
                  ),
                  DropdownButton<String?>(
                    value: _filterStatus,
                    hint: const Text('الحالة'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                      ..._statusLabels.entries.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
                    ],
                    onChanged: (v) => setState(() => _filterStatus = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty) const Text('لا يوجد طلاب مطابقون. أضف طالبًا أو عدّل الفلتر.'),
              ...filtered.map((s) {
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
                              onPressed: () => _removeStudent(s['_key'].toString()),
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

  Future<void> _editLedgerEntry(Map<String, dynamic> entry) async {
    final pointsCtrl = TextEditingController(text: entry['points']?.toString() ?? '0');
    String type = entry['type']?.toString() ?? 'grant';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('تعديل العملية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              TextField(
                controller: pointsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'عدد النقاط'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (result != true) return;
    try {
      await context.read<ApiService>().updateIncentiveTransaction(
            circleId: widget.circleId,
            transactionId: entry['id'].toString(),
            updates: {'type': type, 'points': num.tryParse(pointsCtrl.text) ?? entry['points']},
          );
      if (mounted) setState(_load);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التعديل: $e')));
    }
  }

  List<String> _ledgerRow(Map<String, dynamic> e) => [
        e['studentName']?.toString() ?? '',
        e['itemName']?.toString() ?? '',
        e['type'] == 'grant' ? 'منح' : 'خصم',
        '${e['points'] ?? 0}',
      ];

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('سجل المنح والخصم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Wrap(spacing: 4, children: [
                    IconButton(
                      tooltip: 'طباعة PDF',
                      onPressed: _ledger.isEmpty
                          ? null
                          : () => printTablePdf(
                                title: 'سجل المنح والخصم',
                                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                                rows: _ledger.map(_ledgerRow).toList(),
                              ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                    ),
                    IconButton(
                      tooltip: 'تصدير Excel',
                      onPressed: _ledger.isEmpty
                          ? null
                          : () => exportTableExcel(
                                sheetTitle: 'سجل التحفيز',
                                headers: const ['الطالب', 'البند', 'النوع', 'النقاط'],
                                rows: _ledger.map(_ledgerRow).toList(),
                                fileName: 'سجل_التحفيز.xlsx',
                              ),
                      icon: const Icon(Icons.grid_on_outlined),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 8),
              if (_ledger.isEmpty) const Text('لا توجد عمليات مسجّلة بعد.'),
              ..._ledger.take(50).map((entry) {
                final isGrant = entry['type'] == 'grant';
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(entry['studentName']?.toString() ?? ''),
                    subtitle: Text('${entry['itemName'] ?? ''} · ${isGrant ? '+' : '-'}${entry['points']} نقطة'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editLedgerEntry(entry),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () => _deleteLedgerEntry(entry['id'].toString()),
                        ),
                      ],
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

  static const _statusLabels = {
    'present': 'حاضر',
    'absent': 'غائب',
    'late': 'متأخر',
    'excused': 'مستأذن',
    'leave': 'إجازة',
  };

  static String _statusLabel(String? status) => _statusLabels[status] ?? 'بدون تسجيل';

  static const _statusColors = {
    'present': AppColors.primary,
    'absent': AppColors.danger,
    'late': AppColors.accentOrange,
    'excused': AppColors.accentBlue,
    'leave': Colors.purple,
  };

  static Color _statusColor(String? status) => _statusColors[status] ?? Colors.grey;

  void _showDatesDialog(
      BuildContext context, String title, List<Map<String, dynamic>> records) {
    final dates = records
        .map((r) => r['dateKey']?.toString() ?? '')
        .where((d) => d.isNotEmpty)
        .toList()
      ..sort();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: dates.isEmpty
              ? const Text('لا توجد تواريخ.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: dates.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.event, size: 18),
                    title: Text(dates[i]),
                  ),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _buildSummaryChart(
      int present, int absent, int late, int excused, int leave) {
    final vals = [present, absent, late, excused, leave];
    final labels = ['حاضر', 'غائب', 'تأخر', 'استئذان', 'اجازة'];
    final colors = [
      AppColors.primary,
      AppColors.danger,
      AppColors.accentOrange,
      AppColors.accentBlue,
      Colors.purple,
    ];
    final maxV = vals.fold<int>(0, (m, v) => v > m ? v : m).toDouble();
    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxV <= 0 ? 1 : maxV * 1.2,
          barGroups: List.generate(
              5,
              (i) => BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: vals[i].toDouble(),
                      color: colors[i],
                      width: 22,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ])),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[i], style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
         ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _records.where((r) => r['status'] == 'present').length;
    final absentCount = _records.where((r) => r['status'] == 'absent').length;
    final lateCount = _records.where((r) => r['status'] == 'late').length;
    final excusedCount = _records.where((r) => r['status'] == 'excused').length;
    final leaveCount = _records.where((r) => r['status'] == 'leave').length;
    final Map<String, Map<String, List<Map<String, dynamic>>>> byStudent = {};
    for (final r in _records) {
      final name = (r['studentName'] ?? '').toString();
      if (name.isEmpty) continue;
      final status = (r['status'] ?? '').toString();
      byStudent.putIfAbsent(
          name,
          () => {
                'present': <Map<String, dynamic>>[],
                'absent': <Map<String, dynamic>>[],
                'late': <Map<String, dynamic>>[],
                'excused': <Map<String, dynamic>>[],
                'leave': <Map<String, dynamic>>[],
              });
      if (byStudent[name]!.containsKey(status)) {
        byStudent[name]![status]!.add(r);
      }
    }
    final studentNames = byStudent.keys.toList()..sort();

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
            _buildSummaryChart(presentCount, absentCount, lateCount, excusedCount, leaveCount),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(
                  label: 'حاضر',
                  count: presentCount,
                  color: AppColors.primary,
                  onTap: () => _showDatesDialog(context, 'أيام الحضور',
                      _records.where((r) => r['status'] == 'present').toList()),
                ),
                _StatChip(
                  label: 'غائب',
                  count: absentCount,
                  color: AppColors.danger,
                  onTap: () => _showDatesDialog(context, 'أيام الغياب',
                      _records.where((r) => r['status'] == 'absent').toList()),
                ),
                _StatChip(
                  label: 'تأخر',
                  count: lateCount,
                  color: AppColors.accentOrange,
                  onTap: () => _showDatesDialog(context, 'أيام التأخر',
                      _records.where((r) => r['status'] == 'late').toList()),
                ),
                _StatChip(
                  label: 'استئذان',
                  count: excusedCount,
                  color: AppColors.accentBlue,
                  onTap: () => _showDatesDialog(context, 'أيام الاستئذان',
                      _records.where((r) => r['status'] == 'excused').toList()),
                ),
                _StatChip(
                  label: 'اجازة',
                  count: leaveCount,
                  color: Colors.purple,
                  onTap: () => _showDatesDialog(context, 'أيام الاجازة',
                      _records.where((r) => r['status'] == 'leave').toList()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (studentNames.isNotEmpty) ...[
              const Text('تفصيل الحضور لكل طالب',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              ...studentNames.map((name) {
                final counts = byStudent[name]!;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatChip(
                              label: 'حاضر',
                              count: counts['present']!.length,
                              color: AppColors.primary,
                              onTap: () => _showDatesDialog(
                                  context, '$name - أيام الحضور', counts['present']!),
                            ),
                            _StatChip(
                              label: 'غائب',
                              count: counts['absent']!.length,
                              color: AppColors.danger,
                              onTap: () => _showDatesDialog(
                                  context, '$name - أيام الغياب', counts['absent']!),
                            ),
                            _StatChip(
                              label: 'تأخر',
                              count: counts['late']!.length,
                              color: AppColors.accentOrange,
                              onTap: () => _showDatesDialog(
                                  context, '$name - أيام التأخر', counts['late']!),
                            ),
                            _StatChip(
                              label: 'استئذان',
                              count: counts['excused']!.length,
                              color: AppColors.accentBlue,
                              onTap: () => _showDatesDialog(
                                  context, '$name - أيام الاستئذان', counts['excused']!),
                            ),
                            _StatChip(
                              label: 'اجازة',
                              count: counts['leave']!.length,
                              color: Colors.purple,
                              onTap: () => _showDatesDialog(
                                  context, '$name - أيام الاجازة', counts['leave']!),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 16),
            Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _records.isEmpty
                    ? null
                    : () => printTablePdf(
                          title: 'تقرير حضور الطلاب',
                          subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
                          headers: const ['التاريخ', 'الطالب', 'الحالة'],
                          rows: _records
                              .map((r) => [
                                    r['dateKey']?.toString() ?? '',
                                    r['studentName']?.toString() ?? '',
                                    _statusLabel(r['status']?.toString()),
                                  ])
                              .toList(),
                        ),
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة'),
              ),
              OutlinedButton.icon(
                onPressed: _records.isEmpty
                    ? null
                    : () => exportTableExcel(
                          sheetTitle: 'تحضير الطلاب',
                          headers: const ['التاريخ', 'الطالب', 'الحالة'],
                          rows: _records
                              .map((r) => [
                                    r['dateKey']?.toString() ?? '',
                                    r['studentName']?.toString() ?? '',
                                    _statusLabel(r['status']?.toString()),
                                  ])
                              .toList(),
                          fileName: 'تحضير_الطلاب.xlsx',
                        ),
                icon: const Icon(Icons.grid_on_outlined),
                label: const Text('تصدير Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _records.isEmpty
                      ? null
                      : () => shareTablePdfWhatsApp(
                            title: 'تقرير حضور الطلاب',
                            subtitle: '${_fmt(_fromDate)} إلى ${_fmt(_toDate)}',
                            headers: const ['التاريخ', 'الطالب', 'الحالة'],
                            rows: _records
                                .map((r) => [
                                      r['dateKey']?.toString() ?? '',
                                      r['studentName']?.toString() ?? '',
                                      _statusLabel(r['status']?.toString()),
                                    ])
                                .toList(),
                            fileName: 'تحضير_الطلاب.pdf',
                          ),
                  icon: const Icon(Icons.chat, color: Colors.green),
                  label: const Text('واتساب'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_records.isEmpty) const Text('لا توجد سجلات في هذه الفترة.'),
          ..._records.map((r) {
            final status = r['status']?.toString();
            final color = _statusColor(status);
            return Card(
              child: ListTile(
                dense: true,
                leading: CircleAvatar(backgroundColor: color, radius: 6),
                title: Text(r['studentName']?.toString() ?? ''),
                subtitle: Text(r['dateKey']?.toString() ?? ''),
                trailing: Text(_statusLabel(status), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ],
        const SizedBox(height: 24),
      ],
  );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;
  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
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
