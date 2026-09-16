import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/circle/circle_home_screen.dart';
import 'screens/super_admin/super_admin_home_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // بيانات اللغة (أسماء الأيام والشهور بالعربي) لازم تتحمّل قبل أي استخدام
  // لـ DateFormat(pattern, 'ar') — من غيرها بيرمي LocaleDataException وقت
  // الرسم (زي اللي حصل في شاشة تسجيل حضور المعلم).
  await initializeDateFormatting('ar');

  // تشخيص مؤقت: في وضع release العادي، أي خطأ أثناء رسم أي عنصر بيتحوّل
  // لمربع فاضي تمامًا من غير أي رسالة — وده بالظبط اللي كان بيسبّب "الشاشة الفاضية".
  // هنا بنجبر Flutter يعرض تفاصيل الخطأ الكاملة بدل المربع الفاضي، لحد ما نتأكد
  // المشكلة اتحلت بالكامل.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            'خطأ فادح أثناء الرسم (تشخيص شامل):\n\n'
            '${details.exceptionAsString()}\n\n'
            '${details.stack}',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ),
    );
  };

  runApp(const HalaqatApp());
}

class HalaqatApp extends StatelessWidget {
  const HalaqatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => ApiService()),
      ],
      child: MaterialApp(
        title: 'نظام إدارة الحلقات',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: buildAppTheme(),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: const RootRouter(),
      ),
    );
  }
}

/// يقرر الشاشة المناسبة حسب حالة تسجيل الدخول والدور (superAdmin / owner / teacher)
/// — بديل التنقّل بين page=login / page=main في main.html القديم.
class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(),
          builder: (context, tokenSnap) {
            if (!tokenSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final role = tokenSnap.data!.claims?['role'] as String?;
            final circleId = tokenSnap.data!.claims?['circleId'] as String?;

            if (role == 'superAdmin') return const SuperAdminHomeScreen();
            if ((role == 'owner' || role == 'teacher') && circleId != null) {
              return CircleHomeScreen(circleId: circleId, role: role!);
            }
            // دور غير معروف أو claims لسه ما وصلتش — نرجّع لشاشة الدخول
            return const LoginScreen();
          },
        );
      },
    );
  }
}
