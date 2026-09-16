import 'package:url_launcher/url_launcher.dart';

/// يفتح محادثة واتساب مباشرة مع رقم هاتف معيّن مع رسالة جاهزة —
/// يقابل أيقونة "واتساب" بجانب كل معلم في جدول تحضير المعلمين، وأزرار
/// "إرسال رسالة" في شاشات أخرى، بدون الحاجة لإعداد WhatsApp Business API.
Future<bool> openWhatsApp(String phone, {String message = ''}) async {
  final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.isEmpty) return false;
  // لو الرقم سعودي محلي (يبدأ بـ 0)، نحوّله لصيغة دولية (+966)
  final normalized = clean.startsWith('0') ? '966${clean.substring(1)}' : clean.replaceFirst('+', '');
  final uri = Uri.parse('https://wa.me/$normalized${message.isNotEmpty ? '?text=${Uri.encodeComponent(message)}' : ''}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
