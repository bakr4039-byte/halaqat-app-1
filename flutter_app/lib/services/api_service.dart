import 'package:cloud_functions/cloud_functions.dart';

/// طبقة نداء موحّدة لكل Cloud Functions (بديل google.script.run في main.html القديم).
class ApiService {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ---------- بيانات المجمع الأساسية ----------
  Future<Map<String, dynamic>> getInitialData(String circleId) =>
      _call('getInitialData', {'circleId': circleId});

  Future<Map<String, dynamic>> recordTeacherCheckIn({
    required String circleId,
    required String teacherId,
    required String teacherName,
    required String dateKey,
    required String dayName,
    double? lat,
    double? lng,
  }) => _call('recordTeacherCheckIn', {
        'circleId': circleId, 'teacherId': teacherId, 'teacherName': teacherName,
        'dateKey': dateKey, 'dayName': dayName,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });

  Future<Map<String, dynamic>> recordTeacherCheckOut({
    required String circleId,
    required String teacherId,
    required String dateKey,
    double? lat,
    double? lng,
  }) => _call('recordTeacherCheckOut', {
        'circleId': circleId, 'teacherId': teacherId, 'dateKey': dateKey,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });

  // ---------- الطلاب والحضور ----------
  Future<Map<String, dynamic>> getStudents(String circleId) => _call('getStudents', {'circleId': circleId});

  Future<Map<String, dynamic>> getStudentAttendanceForDate(String circleId, String dateKey) =>
      _call('getStudentAttendanceForDate', {'circleId': circleId, 'dateKey': dateKey});

  Future<Map<String, dynamic>> saveStudentAttendanceDay({
    required String circleId,
    required String dateKey,
    required List<Map<String, dynamic>> records,
  }) => _call('saveStudentAttendanceDay', {'circleId': circleId, 'dateKey': dateKey, 'records': records});

  Future<Map<String, dynamic>> getAttendanceTrend(String circleId) =>
      _call('getAttendanceTrend', {'circleId': circleId});

  Future<Map<String, dynamic>> saveStudents({
    required String circleId,
    required List<Map<String, dynamic>> students,
  }) => _call('saveStudents', {'circleId': circleId, 'students': students});

  Future<Map<String, dynamic>> getStudentAttendanceReport({
    required String circleId,
    required String fromDateKey,
    required String toDateKey,
  }) => _call('getStudentAttendanceReport', {
        'circleId': circleId, 'fromDateKey': fromDateKey, 'toDateKey': toDateKey,
      });

  // ---------- التحفيز ----------
  Future<Map<String, dynamic>> getIncentiveItems(String circleId) =>
      _call('getIncentiveItems', {'circleId': circleId});

  Future<Map<String, dynamic>> saveIncentiveItem({
    required String circleId,
    required Map<String, dynamic> item,
  }) => _call('saveIncentiveItem', {'circleId': circleId, 'item': item});

  Future<Map<String, dynamic>> deleteIncentiveItem({
    required String circleId,
    required String itemId,
  }) => _call('deleteIncentiveItem', {'circleId': circleId, 'itemId': itemId});

  Future<Map<String, dynamic>> getIncentiveLedger(String circleId) =>
      _call('getIncentiveLedger', {'circleId': circleId});

  Future<Map<String, dynamic>> updateIncentiveTransaction({
    required String circleId,
    required String transactionId,
    required Map<String, dynamic> updates,
  }) => _call('updateIncentiveTransaction', {
        'circleId': circleId, 'transactionId': transactionId, 'updates': updates,
      });

  Future<Map<String, dynamic>> deleteIncentiveTransaction({
    required String circleId,
    required String transactionId,
  }) => _call('deleteIncentiveTransaction', {'circleId': circleId, 'transactionId': transactionId});

  Future<Map<String, dynamic>> applyIncentivePointsBulk({
    required String circleId,
    required String itemId,
    required List<String> studentIds,
    required String appliedBy,
  }) => _call('applyIncentivePointsBulk', {
        'circleId': circleId, 'itemId': itemId, 'studentIds': studentIds, 'appliedBy': appliedBy,
      });

  Future<Map<String, dynamic>> getLeaderboard(String circleId) => _call('getLeaderboard', {'circleId': circleId});

  // ---------- التقدم الأكاديمي ----------
  Future<Map<String, dynamic>> getAcademicProgressData(String circleId) =>
      _call('getAcademicProgressData', {'circleId': circleId});

  Future<Map<String, dynamic>> saveAcademicProgressValue({
    required String circleId,
    required String studentId,
    required String studentName,
    required String field,
    required num value,
  }) => _call('saveAcademicProgressValue', {
        'circleId': circleId, 'studentId': studentId, 'studentName': studentName,
        'field': field, 'value': value,
      });

  // ---------- جدول تحضير المعلمين اليومي (لوحة صاحب المجمع) ----------
  Future<Map<String, dynamic>> adminStampTeacherAttendance({
    required String circleId,
    required String teacherId,
    required String teacherName,
    required String dateKey,
    required String dayName,
    required String type, // 'checkIn' | 'checkOut'
  }) => _call('adminStampTeacherAttendance', {
        'circleId': circleId, 'teacherId': teacherId, 'teacherName': teacherName,
        'dateKey': dateKey, 'dayName': dayName, 'type': type,
      });

  Future<Map<String, dynamic>> setTeacherAbsentToday({
    required String circleId,
    required String teacherId,
    required String teacherName,
    required String dateKey,
    required String dayName,
    required bool isAbsent,
  }) => _call('setTeacherAbsentToday', {
        'circleId': circleId, 'teacherId': teacherId, 'teacherName': teacherName,
        'dateKey': dateKey, 'dayName': dayName, 'isAbsent': isAbsent,
      });

  Future<Map<String, dynamic>> getTeacherAttendanceReport({
    required String circleId,
    required String fromDateKey,
    required String toDateKey,
  }) => _call('getTeacherAttendanceReport', {
        'circleId': circleId, 'fromDateKey': fromDateKey, 'toDateKey': toDateKey,
      });

  Future<Map<String, dynamic>> getMonthlyPayroll({
    required String circleId,
    required String fromDateKey,
    required String toDateKey,
  }) => _call('getMonthlyPayroll', {
        'circleId': circleId, 'fromDateKey': fromDateKey, 'toDateKey': toDateKey,
      });

  Future<Map<String, dynamic>> saveTodayAttendanceToSheet({
    required String circleId,
    required String dateKey,
  }) => _call('saveTodayAttendanceToSheet', {'circleId': circleId, 'dateKey': dateKey});

  // ---------- تحضير الطلاب (حالة واحدة فقط) ----------
  Future<Map<String, dynamic>> saveSingleStudentAttendance({
    required String circleId,
    required String dateKey,
    required String studentId,
    required String studentName,
    required String teacherId,
    required String status,
  }) => _call('saveSingleStudentAttendance', {
        'circleId': circleId, 'dateKey': dateKey, 'studentId': studentId,
        'studentName': studentName, 'teacherId': teacherId, 'status': status,
      });

  Future<Map<String, dynamic>> saveTeachersAndSettings({
    required String circleId,
    required List<Map<String, dynamic>> teachers,
    required Map<String, dynamic> settings,
  }) => _call('saveTeachersAndSettings', {
        'circleId': circleId, 'teachers': teachers, 'settings': settings,
      });

  // ---------- السوبر أدمن ----------
  Future<Map<String, dynamic>> superAdminGetOverview() => _call('superAdminGetOverview', {});

  Future<Map<String, dynamic>> superAdminCreateCircle({
    required String circleName,
    required String ownerUsername,
    required String password,
  }) => _call('superAdminCreateCircle', {
        'circleName': circleName, 'ownerUsername': ownerUsername, 'password': password,
      });

  Future<Map<String, dynamic>> superAdminUpdateCircle({
    required String circleId,
    required Map<String, dynamic> updates,
  }) =>
      _call('superAdminUpdateCircle', {'circleId': circleId, 'updates': updates});

  Future<Map<String, dynamic>> superAdminDeleteCircle({
    required String circleId,
  }) =>
      _call('superAdminDeleteCircle', {'circleId': circleId});
}
