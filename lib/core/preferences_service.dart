import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _keyWebsiteFolder = 'website_folder';
  static const String _keyAutoStart = 'auto_start';

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static Future<PreferencesService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs);
  }

  String? getWebsiteFolder() {
    return _prefs.getString(_keyWebsiteFolder);
  }

  Future<void> setWebsiteFolder(String path) async {
    await _prefs.setString(_keyWebsiteFolder, path);
  }

  Future<void> clearWebsiteFolder() async {
    await _prefs.remove(_keyWebsiteFolder);
  }

  bool getAutoStart() {
    return _prefs.getBool(_keyAutoStart) ?? false;
  }

  Future<void> setAutoStart(bool value) async {
    await _prefs.setBool(_keyAutoStart, value);
  }
}
