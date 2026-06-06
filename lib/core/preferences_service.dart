import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _keyWebsiteFolder = 'website_folder';
  static const String _keyAutoStart = 'auto_start';
  static const String _keySubdomain = 'subdomain';
  static const String _keyTunnelEnabled = 'tunnel_enabled';
  static const String _keyTunnelToken = 'tunnel_token';

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

  String? getSubdomain() {
    return _prefs.getString(_keySubdomain);
  }

  Future<void> setSubdomain(String subdomain) async {
    await _prefs.setString(_keySubdomain, subdomain);
  }

  bool getTunnelEnabled() {
    return _prefs.getBool(_keyTunnelEnabled) ?? false;
  }

  Future<void> setTunnelEnabled(bool value) async {
    await _prefs.setBool(_keyTunnelEnabled, value);
  }

  String getTunnelToken() {
    return _prefs.getString(_keyTunnelToken) ?? '';
  }

  Future<void> setTunnelToken(String token) async {
    await _prefs.setString(_keyTunnelToken, token);
  }
}
