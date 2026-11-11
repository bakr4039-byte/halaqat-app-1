import 'dart:async';
import 'package:flutter/material.dart';

/// Owns listener cleanup so hidden/closed screens cannot receive late setState.
mixin LiveRefreshMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _liveSubscription;
  bool _reportedLiveError = false;

  void listenForLiveUpdates(Stream<void> changes, VoidCallback reload) {
    _liveSubscription?.cancel();
    _liveSubscription = changes.listen((_) {
      if (mounted) reload();
    }, onError: (Object error) {
      if (!mounted || _reportedLiveError) return;
      _reportedLiveError = true;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('تعذرت المزامنة المباشرة. حدّث الصفحة، وتحقق من الاتصال وصلاحيات الحساب.'),
      ));
    });
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    super.dispose();
  }
}
