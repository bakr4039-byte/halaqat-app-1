/// أدوات مساعدة للتعامل مع البيانات الراجعة من Cloud Functions.
///
/// البيانات الراجعة من HttpsCallable بتتفكّك عبر platform channel، وعناصر
/// أي List جوّاها بتكون Map<Object?, Object?> خام مش Map<String, dynamic> —
/// استخدام `.cast<Map<String, dynamic>>()` عليها وحده مش كافي لأنه "كسول"
/// (lazy): بيرجّع View من غير ما يتحقق من النوع فعليًا، وبيفشل فجأة وقت
/// القراءة الحقيقية (زي `list[i]` جوّه ListView.builder) — وده كان سبب
/// مشكلة "الشاشة الفاضية" في لوحة السوبر أدمن.
///
/// الحل: تحويل حقيقي (deep) لكل عنصر عبر Map<String, dynamic>.from().
library;

/// يحوّل List من عناصر Map خام (زي الراجعة من Cloud Functions) إلى
/// List<Map<String, dynamic>> حقيقية وآمنة للقراءة.
List<Map<String, dynamic>> asMapList(dynamic raw) {
  if (raw == null) return <Map<String, dynamic>>[];
  return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// يحدّد هل الطالب [student] "مسند" للمعلم صاحب [teacherId] أو لا.
/// [teacherId] فاضي (null) معناها مفيش فلترة أصلًا (شاشة أدمن) فبيرجع true
/// للكل. غير كده، الطالب يُعتبر مسند للمعلم في حالتين:
/// 1) تخصيص مباشر: حقل teacherId على الطالب نفسه يطابق [teacherId].
/// 2) تخصيص عبر الحلقة الفرعية: المعلم نفسه مسند لحلقة فرعية معيّنة (حقل
///    subCircle في بيانات المعلم) وبيانات الطالب لنفس الحلقة الفرعية —
///    ده اللي بيغطي حالة إن الأدمن ربط المعلم بحلقة فرعية كاملة بدل ما
///    يحدد كل طالب لوحده.
/// [teachers] هي قائمة المعلمين الخام (زي الراجعة من getInitialData).
bool studentBelongsToTeacher(
  Map<String, dynamic> student,
  String? teacherId,
  List<Map<String, dynamic>> teachers,
) {
  if (teacherId == null || teacherId.isEmpty) return true;
  if (student['teacherId']?.toString() == teacherId) return true;

  String? teacherSubCircle;
  for (final t in teachers) {
    if (t['id']?.toString() == teacherId) {
      teacherSubCircle = t['subCircle']?.toString();
      break;
    }
  }
  if (teacherSubCircle == null || teacherSubCircle.isEmpty) return false;
  return (student['subCircle']?.toString() ?? '') == teacherSubCircle;
}
