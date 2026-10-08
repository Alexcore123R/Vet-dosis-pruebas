import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final int palette;
  final String brightness;
  const AppSettings({this.palette = 0, this.brightness = 'system'});
}

class SettingsRepository {
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final palette = prefs.getInt('palette') ?? 0;
    final mode = prefs.getString('brightness') ?? 'system';
    return AppSettings(
      palette: palette >= 0 && palette < 5 ? palette : 0,
      brightness: ['system', 'light', 'dark'].contains(mode) ? mode : 'system',
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setInt('palette', settings.palette) ||
        !await prefs.setString('brightness', settings.brightness)) {
      throw StateError('settings_not_saved');
    }
  }
}
