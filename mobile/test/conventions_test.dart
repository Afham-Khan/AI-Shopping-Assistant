import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards project conventions that the analyzer can't enforce.
void main() {
  test('lib/ imports material_ui, never package:flutter/material.dart', () {
    // go_router, google_fonts, riverpod… all use material_ui; mixing the two
    // libraries gives two incompatible ThemeData/MaterialApp types.
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains("package:flutter/material.dart"))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'Use package:material_ui/material_ui.dart instead');
  });
}
