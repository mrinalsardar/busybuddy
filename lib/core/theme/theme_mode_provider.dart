import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This device's preference store, loaded by `main` before the first frame.
/// Null when it could not be loaded: a theme choice then lasts only until the
/// app closes.
final preferencesProvider = Provider<SharedPreferences?>((_) => null);

/// The chosen theme: light, dark, or following the device setting. Kept per
/// device, outside the synced database, so signing out does not reset it.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const prefsKey = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.watch(preferencesProvider)?.get(prefsKey);
    // Nothing saved, or a value this version does not know: follow the device.
    return ThemeMode.values.where((m) => m.name == saved).firstOrNull ?? ThemeMode.system;
  }

  /// Applies [mode] and saves it. Throws if it cannot be saved; the mode stays
  /// applied until the app closes.
  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = ref.read(preferencesProvider);
    if (prefs == null || !await prefs.setString(prefsKey, mode.name)) {
      throw StateError('The theme choice could not be saved on this device');
    }
  }
}
