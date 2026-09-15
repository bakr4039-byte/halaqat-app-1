import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import 'academic_progress_screen.dart';
import 'incentives_screen.dart';
import 'student_attendance_screen.dart';
import 'teacher_checkin_screen.dart';

/// الشاشة الرئيسية لصاحب المجمع/المعلم بعد تسجيل الدخول —
/// بديل الصفحة الواحدة (Single Page App) في main.html القديم، هنا بتنقّل سفلي.
class CircleHomeScreen extends StatefulWidget {
  final String circleId;
  final String role; // 'owner' | 'teacher'

  const CircleHomeScreen({super.key, required this.circleId, required this.role});

  @override
  State<CircleHomeScreen> createState() => _CircleHomeScreenState();
}

class _CircleHomeScreenState extends State<CircleHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      TeacherCheckinScreen(circleId: widget.circleId),
      StudentAttendanceScreen(circleId: widget.circleId),
      IncentivesScreen(circleId: widget.circleId),
      AcademicProgressScreen(circleId: widget.circleId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام إدارة الحلقات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'حضوري'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'الطلاب'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'التحفيز'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'التقدم'),
        ],
      ),
    );
  }
}
