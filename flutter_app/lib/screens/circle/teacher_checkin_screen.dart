import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/json_utils.dart';

/// يقابل تحضير/انصراف المعلم (recordTeacherCheckIn / recordTeacherCheckOut) في Code.gs
/// — بما فيها الموقع الجغرافي وقت التسجيل.
class TeacherCheckinScreen extends StatefulWidget {
  final String circleId;
  final String? teacherId;
  const TeacherCheckinScreen({super.key, required this.circleId, this.teacherId});

  @override
  State<TeacherCheckinScreen> createState() => _TeacherCheckinScreenState();
}

class _TeacherCheckinScreenState extends State<TeacherCheckinScreen> {
  bool _loading = false;
  bool _loadingName = true;
  String? _message;
  String? _teacherName;

  String get _dateKey => intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get _dayName => intl.DateFormat('EEEE', 'ar').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadTeacherName();
  }

  Future<void> _loadTeacherName() async {
    if (widget.teacherId == null) {
      setState(() => _loadingName = false);
      return;
    }
    try {
      final res = await context.read<ApiService>().getInitialData(widget.circleId);
      final teachers = asMapList(res['teachers']);
      final match = teachers.where((t) => t['id']?.toString() == widget.teacherId).toList();
      if (mounted) {
        setState(() {
          _teacherName = match.isNotEmpty ? match.first['name']?.toString() : null;
          _loadingName = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingName = false);
    }
  }

  /// يجيب الموقع الجغرافي الحالي — لو الصلاحية مرفوضة أو الخدمة مقفولة،
  /// بيرجع null بدل ما يمنع تسجيل الحضور/الانصراف بالكامل.
  Future<Position?> _tryGetLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkIn() async {
    if (widget.teacherId == null) {
      setState(() => _message = 'حسابك غير مربوط بمعلم محدد في هذا المجمع. تواصل مع صاحب المجمع.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final position = await _tryGetLocation();
      final api = context.read<ApiService>();
      final res = await api.recordTeacherCheckIn(
        circleId: widget.circleId,
        teacherId: widget.teacherId!,
        teacherName: _teacherName ?? '',
        dateKey: _dateKey,
        dayName: _dayName,
        lat: position?.latitude,
        lng: position?.longitude,
      );
      final locationNote = position == null ? ' (بدون موقع جغرافي — تأكد من تفعيل خدمة الموقع)' : '';
      setState(() => _message =
          res['success'] == true ? 'تم تسجيل الحضور بنجاح.$locationNote' : (res['message'] ?? 'حدث خطأ'));
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkOut() async {
    if (widget.teacherId == null) {
      setState(() => _message = 'حسابك غير مربوط بمعلم محدد في هذا المجمع. تواصل مع صاحب المجمع.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final position = await _tryGetLocation();
      final api = context.read<ApiService>();
      final res = await api.recordTeacherCheckOut(
        circleId: widget.circleId,
        teacherId: widget.teacherId!,
        dateKey: _dateKey,
        lat: position?.latitude,
        lng: position?.longitude,
      );
      final locationNote = position == null ? ' (بدون موقع جغرافي — تأكد من تفعيل خدمة الموقع)' : '';
      setState(() => _message =
          res['success'] == true ? 'تم تسجيل الانصراف بنجاح.$locationNote' : (res['message'] ?? 'حدث خطأ'));
    } catch (e) {
      setState(() => _message = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loadingName)
              const Padding(padding: EdgeInsets.only(bottom: 12), child: CircularProgressIndicator())
            else if (_teacherName != null)
              Text(_teacherName!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(intl.DateFormat('EEEE dd MMMM yyyy', 'ar').format(DateTime.now()),
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                SizedBox(width: 4),
                Text('يتم تسجيل موقعك الجغرافي وقت الحضور/الانصراف', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _checkIn,
                    icon: const Icon(Icons.login),
                    label: const Text('تسجيل حضور'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _checkOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('تسجيل انصراف'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 20),
              Text(_message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
