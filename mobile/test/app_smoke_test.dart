import 'package:cartwise/app.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _boot(WidgetTester tester, Map<String, Object> prefsValues, Size size) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ZeloraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  testWidgets('first launch shows onboarding', (tester) async {
    await _boot(tester, {}, const Size(390, 844));
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning visitor lands on login, guest mode opens the shell', (tester) async {
    await _boot(tester, {StorageKeys.onboardingDone: true}, const Size(320, 640));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with demo account'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-bottom-nav')), findsOneWidget);
    expect(find.text('Zel'), findsOneWidget);
    expect(find.byKey(const Key('app-frame')), findsNothing); // phones are not framed
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop renders the mobile app in a centred column; protected tab asks to sign in', (tester) async {
    await _boot(tester, {StorageKeys.onboardingDone: true, StorageKeys.guestChosen: true}, const Size(1280, 800));
    // mobile everywhere: framed phone column + bottom bar, no top navbar / rail
    expect(find.byKey(const Key('app-frame')), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-nav')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.getSize(find.byKey(const Key('app-frame'))).width, lessThanOrEqualTo(500));

    // the hidden keyboard extra: Ctrl K opens the command palette
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Search products, categories or pages'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Search products, categories or pages'), findsNothing);

    await tester.tap(find.byTooltip('Cart'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings screen renders', (tester) async {
    await _boot(tester, {StorageKeys.onboardingDone: true, StorageKeys.guestChosen: true}, const Size(390, 844));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
