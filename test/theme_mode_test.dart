import 'package:busybuddy/core/models/models.dart';
import 'package:busybuddy/core/providers/core_providers.dart';
import 'package:busybuddy/core/router/app_router.dart';
import 'package:busybuddy/core/theme/app_colors.dart';
import 'package:busybuddy/core/theme/theme_mode_provider.dart';
import 'package:busybuddy/features/settings/providers/settings_providers.dart';
import 'package:busybuddy/features/settings/screens/settings_screen.dart';
import 'package:busybuddy/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeProfile extends StateNotifier<AsyncValue<BusinessProfile?>>
    implements ActiveProfileNotifier {
  _FakeProfile()
      : super(const AsyncValue.data(
            BusinessProfile(id: 'shop-1', name: 'Shop', type: BusinessType.general)));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SharedPreferences> _prefs([String? saved]) async {
  SharedPreferences.setMockInitialValues(
      {ThemeModeNotifier.prefsKey: ?saved});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences? prefs) {
  final container =
      ProviderContainer(overrides: [preferencesProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  return container;
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

void main() {
  group('saved theme choice', () {
    test('is System when nothing is saved', () async {
      expect(_container(await _prefs()).read(themeModeProvider), ThemeMode.system);
    });

    test('is System when the saved value is unknown', () async {
      expect(_container(await _prefs('sepia')).read(themeModeProvider), ThemeMode.system);
    });

    for (final mode in ThemeMode.values) {
      test('${mode.name} survives a restart', () async {
        final prefs = await _prefs();
        await _container(prefs).read(themeModeProvider.notifier).set(mode);
        expect(prefs.getString(ThemeModeNotifier.prefsKey), mode.name);
        expect(_container(prefs).read(themeModeProvider), mode);
      });
    }

    test('applies without a preference store, and reports that it is not saved', () async {
      final container = _container(null);
      await expectLater(
          container.read(themeModeProvider.notifier).set(ThemeMode.light), throwsStateError);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });
  });

  group('mode selection in Settings', () {
    Future<SharedPreferences> pump(WidgetTester tester,
        {String? saved, bool isOwner = true}) async {
      final prefs = await _prefs(saved);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          activeProfileProvider.overrideWith((ref) => _FakeProfile()),
          isOwnerProvider.overrideWithValue(isOwner),
          canEditCurrencyProvider.overrideWith((ref) async => false),
          routerProvider.overrideWithValue(GoRouter(
              routes: [GoRoute(path: '/', builder: (_, _) => const SettingsScreen())])),
        ],
        child: const BusyBuddyApp(),
      ));
      await tester.pumpAndSettle();
      return prefs;
    }

    ThemeData theme(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(SettingsScreen)));

    Set<ThemeMode> selected(WidgetTester tester) => tester
        .widget<SegmentedButton<ThemeMode>>(find.byType(SegmentedButton<ThemeMode>))
        .selected;

    void setDevice(WidgetTester tester, Brightness brightness) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    }

    testWidgets('System follows the device, also while running', (tester) async {
      setDevice(tester, Brightness.light);
      await pump(tester);
      expect(selected(tester), {ThemeMode.system});
      expect(theme(tester).brightness, Brightness.light);
      expect(theme(tester).extension<AppColors>(), AppColors.light);

      setDevice(tester, Brightness.dark);
      await tester.pumpAndSettle();
      expect(theme(tester).brightness, Brightness.dark);
      expect(theme(tester).extension<AppColors>(), AppColors.dark);
    });

    testWidgets('Light and Dark override the device and are saved', (tester) async {
      setDevice(tester, Brightness.dark);
      final prefs = await pump(tester);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(selected(tester), {ThemeMode.light});
      expect(theme(tester).brightness, Brightness.light);
      expect(prefs.getString(ThemeModeNotifier.prefsKey), 'light');

      setDevice(tester, Brightness.light);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(theme(tester).brightness, Brightness.dark);
      expect(prefs.getString(ThemeModeNotifier.prefsKey), 'dark');

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(theme(tester).brightness, Brightness.light);
      expect(prefs.getString(ThemeModeNotifier.prefsKey), 'system');
    });

    testWidgets('the saved choice applies from the first frame', (tester) async {
      setDevice(tester, Brightness.dark);
      await pump(tester, saved: 'light');
      expect(selected(tester), {ThemeMode.light});
      expect(theme(tester).brightness, Brightness.light);
    });

    testWidgets('staff can change it too', (tester) async {
      await pump(tester, saved: 'dark', isOwner: false);
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(theme(tester).brightness, Brightness.light);
    });

    testWidgets('system bar icons contrast with the theme', (tester) async {
      await pump(tester, saved: 'light');
      SystemUiOverlayStyle style() => tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first)
          .value;
      expect(style().systemNavigationBarIconBrightness, Brightness.dark);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(style().systemNavigationBarIconBrightness, Brightness.light);
      expect(style().systemNavigationBarColor, AppColors.dark.card);
    });
  });

  test('light theme text colours are readable on its surfaces', () {
    const c = AppColors.light;
    for (final color in [
      c.textPrimary, c.textSecondary, c.accent, c.warning, c.error, c.success,
    ]) {
      for (final surface in [c.background, c.card]) {
        expect(_contrast(color, surface), greaterThanOrEqualTo(4.5), reason: '$color on $surface');
      }
    }
  });
}
