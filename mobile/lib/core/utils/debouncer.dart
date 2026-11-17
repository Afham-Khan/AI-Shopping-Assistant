import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs only the last action after [duration] of quiet (search-as-you-type).
///
/// ```dart
/// final _debouncer = Debouncer();
/// onChanged: (q) => _debouncer.run(() => search(q)),
/// dispose() => _debouncer.dispose();
/// ```
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 350)});

  final Duration duration;
  Timer? _timer;

  bool get isPending => _timer?.isActive ?? false;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => cancel();
}
