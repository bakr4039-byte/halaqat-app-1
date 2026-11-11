import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

/// Firebase Hosting supplies the registered web app's public configuration.
/// Android and iOS keep their existing, generated platform configuration.
Future<void> initializeSharedFirebase() async {
  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    return;
  }
  const appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  const apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  Map<String, dynamic> config;
  if (appId.isNotEmpty && apiKey.isNotEmpty) {
    config = {
      'appId': appId,
      'apiKey': apiKey,
      'projectId': DefaultFirebaseOptions.android.projectId,
      'messagingSenderId': DefaultFirebaseOptions.android.messagingSenderId,
      'authDomain': '${DefaultFirebaseOptions.android.projectId}.firebaseapp.com',
      'storageBucket': DefaultFirebaseOptions.android.storageBucket,
    };
  } else {
    final response = await http.get(Uri.base.resolve('/__/firebase/init.json'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('سجّل تطبيق ويب في مشروع Firebase ثم انشره على Firebase Hosting.');
    }
    config = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
  if (config['projectId'] != DefaultFirebaseOptions.android.projectId ||
      (config['appId']?.toString().isEmpty ?? true) ||
      (config['apiKey']?.toString().isEmpty ?? true)) {
    throw StateError('إعدادات الويب لا تطابق مشروع تطبيق أندرويد.');
  }
  await Firebase.initializeApp(options: FirebaseOptions(
    apiKey: config['apiKey'] as String,
    appId: config['appId'] as String,
    messagingSenderId: config['messagingSenderId'].toString(),
    projectId: config['projectId'] as String,
    authDomain: config['authDomain'] as String?,
    storageBucket: config['storageBucket'] as String?,
  ));
}
