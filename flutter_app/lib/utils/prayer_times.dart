import 'dart:convert';
import 'package:http/http.dart' as http;

/// يجيب أوقات الصلاة ليوم النهاردة من Aladhan API (خدمة مجانية بدون مفتاح) —
/// يقابل "مؤشر الأذان والوقت المستهدف" في لوحة تحكم المعلمين.
class PrayerTimesResult {
  final Map<String, String> timings; // Fajr, Dhuhr, Asr, Maghrib, Isha ...
  PrayerTimesResult(this.timings);
}

Future<PrayerTimesResult?> fetchPrayerTimes(String city, {String country = 'Saudi Arabia'}) async {
  try {
    final uri = Uri.parse(
      'https://api.aladhan.com/v1/timingsByCity?city=${Uri.encodeComponent(city)}&country=${Uri.encodeComponent(country)}&method=4',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final timings = Map<String, dynamic>.from(body['data']?['timings'] ?? {});
    return PrayerTimesResult(timings.map((k, v) => MapEntry(k, v.toString())));
  } catch (_) {
    return null;
  }
}

const Map<String, String> prayerSlotLabelsArabic = {
  'Fajr': 'الفجر',
  'Dhuhr': 'الظهر',
  'Asr': 'العصر',
  'Maghrib': 'المغرب',
  'Isha': 'العشاء',
};
