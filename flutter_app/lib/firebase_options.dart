// ملف تلقائي التوليد — placeholder مؤقت فقط.
//
// لازم تستبدل الملف ده بالنسخة الحقيقية بعد ما تعمل مشروع Firebase بتاعك:
//   1) dart pub global activate flutterfire_cli
//   2) flutterfire configure --project=<your-firebase-project-id>
// الأمر ده هيسأل عن المنصات (android/ios) وهيولّد القيم الصحيحة تلقائيًا
// بدل القيم الوهمية تحت، وهيربط التطبيق فعليًا بمشروعك.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('نسخة الويب غير مُعدّة بعد — التطبيق مُجهّز لأندرويد وآيفون فقط حاليًا.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('منصة غير مدعومة: $defaultTargetPlatform');
    }
  }

  // ⚠️ قيم placeholder — استبدلها بمخرجات flutterfire configure الحقيقية
  static const android = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME.appspot.com',
  );

  static const ios = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME.appspot.com',
    iosBundleId: 'com.halaqat.app',
  );
}
