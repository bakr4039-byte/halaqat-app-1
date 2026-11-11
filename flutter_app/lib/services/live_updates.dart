import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Invalidation events shared by Android and web. The first snapshot is already
/// covered by each screen's initial load; later server changes refresh its data.
Stream<void> watchSchoolChanges(String circleId, {String? teacherId}) {
  final db = FirebaseFirestore.instance;
  final circle = db.collection('circles').doc(circleId);
  final streams = <Stream<dynamic>>[circle.snapshots()];
  for (final name in ['students', 'studentAttendance', 'academicProgress', 'teacherAttendance']) {
    Query<Map<String, dynamic>> query = circle.collection(name);
    if (teacherId != null) query = query.where('teacherId', isEqualTo: teacherId);
    streams.add(query.snapshots());
  }
  if (teacherId == null) {
    streams.add(circle.collection('teachers').snapshots());
    streams.add(circle.collection('incentiveLedger').snapshots());
  } else {
    streams.add(circle.collection('teachers').doc(teacherId).snapshots());
    // Legacy incentive entries have subCircle/studentId rather than teacherId.
    // Their protected reads stay in Cloud Functions; other live collections
    // continue to update without requesting another teacher's records.
  }
  streams.add(circle.collection('incentiveItems').snapshots());
  return _changes(streams);
}

Stream<void> watchOwnerChanges() {
  final db = FirebaseFirestore.instance;
  return _changes([
    db.collection('circles').snapshots(),
    db.collectionGroup('students').snapshots(),
    db.collectionGroup('teachers').snapshots(),
    db.collectionGroup('studentAttendance').snapshots(),
  ]);
}

Stream<void> _changes(List<Stream<dynamic>> sources) {
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? debounce;
  late StreamController<void> controller;
  controller = StreamController<void>(
    onListen: () {
      for (final source in sources) {
        var first = true;
        subscriptions.add(source.listen((_) {
          if (first) { first = false; return; }
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 400), () {
            if (!controller.isClosed) controller.add(null);
          });
        }, onError: controller.addError));
      }
    },
    onCancel: () async {
      debounce?.cancel();
      await Future.wait(subscriptions.map((s) => s.cancel()));
    },
  );
  return controller.stream;
}
