import 'package:flutter_test/flutter_test.dart';
import 'package:halaqat_app/utils/json_utils.dart';

void main() {
  final teachers = <Map<String, dynamic>>[
    {'id': 'teacher-a', 'subCircle': 'نافع'},
    {'id': 'teacher-b', 'subCircle': 'نافع'},
  ];
  test('explicit assignment takes priority over a shared sub-circle', () {
    final student = {'teacherId': 'teacher-b', 'subCircle': 'نافع'};
    expect(studentBelongsToTeacher(student, 'teacher-a', teachers), isFalse);
    expect(studentBelongsToTeacher(student, 'teacher-b', teachers), isTrue);
  });
  test('legacy students use a known teacher sub-circle only', () {
    expect(studentBelongsToTeacher({'subCircle': 'نافع'}, 'teacher-a', teachers), isTrue);
    expect(studentBelongsToTeacher({'subCircle': 'عاصم'}, 'teacher-a', teachers), isFalse);
    expect(studentBelongsToTeacher({'subCircle': 'نافع'}, 'unknown', teachers), isFalse);
  });
}
