import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// خدمة المصادقة — بتنادي دالة login في Cloud Functions (username/password)
/// وبعدين بتسجّل دخول Firebase Auth بالـ custom token اللي بترجع.
/// نفس فكرة superAdminLogin / loginUser / loginTeacherView في Code.gs القديم،
/// لكن دلوقتي عبر Firebase Auth حقيقي بدل مقارنة نصوص.
class AuthService extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? _role;
  String? _circleId;
  String? get role => _role;
  String? get circleId => _circleId;

  /// يسجّل الدخول بـ username/password ويحدّد الدور (superAdmin/owner/teacher)
  Future<void> login(String username, String password) async {
    final callable = _functions.httpsCallable('login');
    final result = await callable.call<Map<String, dynamic>>({
      'username': username,
      'password': password,
    });

    final data = result.data;
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'فشل تسجيل الدخول.');
    }

    final token = data['token'] as String;
    await _auth.signInWithCustomToken(token);

    // نجبر تحديث الـ ID token عشان الـ custom claims (role/circleId) تبقى متاحة فورًا
    await _auth.currentUser?.getIdTokenResult(true);
    final claims = (await _auth.currentUser?.getIdTokenResult())?.claims;
    _role = claims?['role'] as String?;
    _circleId = claims?['circleId'] as String?;
    notifyListeners();
  }

  Future<void> refreshClaims() async {
    final claims = (await _auth.currentUser?.getIdTokenResult(true))?.claims;
    _role = claims?['role'] as String?;
    _circleId = claims?['circleId'] as String?;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _role = null;
    _circleId = null;
    notifyListeners();
  }
}
