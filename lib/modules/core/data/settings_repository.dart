import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final int palette;
  final String brightness;
  final String visualStyle;
  const AppSettings({
    this.palette = 0,
    this.brightness = 'system',
    this.visualStyle = 'neu',
  });
}

class SettingsRepository {
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final palette = prefs.getInt('palette') ?? 0;
    final mode = prefs.getString('brightness') ?? 'system';
    final visualStyle = prefs.getString('visualStyle') ?? 'neu';
    return AppSettings(
      visualStyle: ['standard', 'neu'].contains(visualStyle)
          ? visualStyle
          : 'standard',
      palette: palette >= 0 && palette < 5 ? palette : 0,
      brightness: ['system', 'light', 'dark'].contains(mode) ? mode : 'system',
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setInt('palette', settings.palette) ||
        !await prefs.setString('brightness', settings.brightness) ||
        !await prefs.setString('visualStyle', settings.visualStyle)) {
      throw StateError('settings_not_saved');
    }
  }
}
