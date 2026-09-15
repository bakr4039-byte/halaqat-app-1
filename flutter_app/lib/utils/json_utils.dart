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
