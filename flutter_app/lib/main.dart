import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
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
