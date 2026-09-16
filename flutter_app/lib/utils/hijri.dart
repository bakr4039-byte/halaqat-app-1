/// تحويل تقريبي من التاريخ الميلادي إلى الهجري (خوارزمية أم القرى المبسّطة) —
/// يقابل خيار "تعيين نوع التقويم (هجري / ميلادي)" في جدول تحضير المعلمين.
/// ملاحظة: تحويل حسابي تقريبي (±يوم واحد أحيانًا)، وليس بديلاً عن تقويم أم
/// القرى الرسمي، وهو كافٍ للعرض التقديمي في الجدول.
class HijriDate {
  final int year;
  final int month;
  final int day;
  const HijriDate(this.year, this.month, this.day);

  static const _monthNames = [
    'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة',
    'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
  ];

  String get monthName => _monthNames[(month - 1).clamp(0, 11)];

  @override
  String toString() => '$day $monthName $year هـ';
}

HijriDate gregorianToHijri(DateTime date) {
  final jd = _gregorianToJulianDay(date.year, date.month, date.day);
  final l = jd - 1948440 + 10632;
  final n = ((l - 1) / 10631).floor();
  var l2 = l - 10631 * n + 354;
  final j = ((10985 - l2) / 5316).floor() * ((50 * l2) / 17719).floor() +
      (l2 / 5670).floor() * ((43 * l2) / 15238).floor();
  l2 = l2 -
      ((30 - j) / 15).floor() * ((17719 * j) / 50).floor() -
      (j / 16).floor() * ((15238 * j) / 43).floor() +
      29;
  final month = ((24 * l2) / 709).floor();
  final day = l2 - ((709 * month) / 24).floor();
  final year = 30 * n + j - 30;
  return HijriDate(year, month, day);
}

int _gregorianToJulianDay(int year, int month, int day) {
  final a = ((14 - month) / 12).floor();
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day +
      ((153 * m + 2) / 5).floor() +
      365 * y +
      (y / 4).floor() -
      (y / 100).floor() +
      (y / 400).floor() -
      32045;
}
