import 'dart:io';

import 'package:cartwise/app.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/core/theme/app_typography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plus Jakarta Sans is bundled in `assets/google_fonts/`, so google_fonts must
/// resolve every weight the app uses from the asset bundle and never fetch.
///
/// With `allowRuntimeFetching = false` google_fonts throws (instead of going to
/// the network) when a weight has no bundled file, and `pendingFonts()` surfaces
/// that — so "the pending futures complete" == "everything came from assets".
final _bundled = {
  FontWeight.w400: 'Regular',
  FontWeight.w500: 'Medium',
  FontWeight.w600: 'SemiBold',
  FontWeight.w700: 'Bold',
  FontWeight.w800: 'ExtraBold',
};

void main() {
  setUpAll(() {
    AppTheme.useGoogleFonts = true;
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = true;
    AppTheme.useGoogleFonts = false;
  });

  testWidgets('every bundled weight (and the licence) is declared as an asset', (tester) async {
    final manifest = await tester.runAsync(() => AssetManifest.loadFromAssetBundle(rootBundle));
    final assets = manifest!.listAssets();
    for (final name in _bundled.values) {
      expect(assets, contains('assets/google_fonts/PlusJakartaSans-$name.ttf'));
    }
    expect(assets, contains('assets/google_fonts/OFL.txt'));
  });

  testWidgets('each weight resolves from assets, loads, and renders with its own face (not the test font)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final weight in _bundled.keys) {
        // creating the style kicks off the (asset) load
        GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: weight);
        AppType.sans(TextStyle(fontSize: 20, fontWeight: weight));
      }
      await GoogleFonts.pendingFonts(); // throws if any weight was not found in assets
    });

    double width(FontWeight w) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'Zelora gadgets & more',
          style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: w),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    // the flutter_test fallback font (Ahem) is a 1em square per glyph: 21 chars * 20px
    const ahem = 21 * 20.0;
    final widths = {for (final w in _bundled.keys) w: width(w)};
    for (final entry in widths.entries) {
      expect(entry.value, isNot(closeTo(ahem, 1)), reason: '${entry.key} fell back to the test font');
    }
    // heavier cuts are wider — five distinct files, not one font reused
    expect(widths.values.toSet().length, _bundled.length, reason: '$widths');
    expect(widths[FontWeight.w800]!, greaterThan(widths[FontWeight.w400]!));
  });

  testWidgets('the themed app boots with runtime fetching off: no font errors, no exceptions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // build both themes inside runAsync so their font loads run on the real event loop
    await tester.runAsync(() async {
      AppTheme.light;
      AppTheme.dark;
      await GoogleFonts.pendingFonts();
    });

    await tester.pumpWidget(
      ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)], child: const ZeloraApp()),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => GoogleFonts.pendingFonts());

    expect(find.text('Skip'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // the title text really uses a google_fonts family backed by the bundled files
    final family = DefaultTextStyle.of(tester.element(find.text('Skip'))).style.fontFamily;
    expect(family, startsWith('PlusJakartaSans_'));
  });

  testWidgets('guard: a weight that is not bundled fails loudly instead of fetching', (tester) async {
    Object? error;
    await tester.runAsync(() async {
      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w300); // "Light" is not shipped
      try {
        await GoogleFonts.pendingFonts();
      } catch (e) {
        error = e;
      }
    });
    expect(error, isNotNull);
    expect(error.toString(), contains('allowRuntimeFetching is false'));
  });

  test('lib/ only asks for weights that are bundled (w400-w800)', () {
    // google_fonts would need PlusJakartaSans-Light/Thin/Black.ttf for these.
    final unbundled = RegExp(r'FontWeight\.w(100|200|300|900)\b');
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => unbundled.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'Bundle the extra weight in assets/google_fonts/ or use w400-w800');
  });
}
