import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import 'academic_progress_screen.dart';
import 'circle_management_screen.dart';
import 'incentives_screen.dart';
import 'my_data_screen.dart';
import 'student_attendance_screen.dart';
import 'teacher_checkin_screen.dart';

/// الشاشة الرئيسية لصاحب المجمع/المعلم بعد تسجيل الدخول —
/// بديل الصفحة الواحدة (Single Page App) في main.html القديم، هنا بتنقّل سفلي.
class CircleHomeScreen extends StatefulWidget {
  final String circleId;
  final String role; // 'owner' | 'teacher'
  final String? teacherId; // متوفر فقط لما role == 'teacher'

  const CircleHomeScreen({
    super.key,
    required this.circleId,
    required this.role,
    this.teacherId,
  });

  @override
  State<CircleHomeScreen> createState() => _CircleHomeScreenState();
}

class _CircleHomeScreenState extends State<CircleHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.role == 'owner';
    final isTeacher = widget.role == 'teacher';

    final screens = [
      if (isOwner) CircleManagementScreen(circleId: widget.circleId),
      TeacherCheckinScreen(circleId: widget.circleId, teacherId: widget.teacherId),
      StudentAttendanceScreen(
        circleId: widget.circleId,
        filterTeacherId: isTeacher ? widget.teacherId : null,
      ),
      IncentivesScreen(circleId: widget.circleId),
      AcademicProgressScreen(circleId: widget.circleId),
      if (isTeacher) MyDataScreen(circleId: widget.circleId, teacherId: widget.teacherId),
    ];

    final destinations = [
      if (isOwner)
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'إدارة',
        ),
      const NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'حضوري'),
      const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'الطلاب'),
      const NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'التحفيز'),
      const NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'التقدم'),
      if (isTeacher)
        const NavigationDestination(icon: Icon(Icons.insert_chart_outlined), selectedIcon: Icon(Icons.insert_chart), label: 'بياناتي'),
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
        destinations: destinations,
      ),
    );
  }
}
