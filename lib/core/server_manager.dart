import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'visitor_tracker.dart';
import 'network_utils.dart';
import 'preferences_service.dart';
import 'webrtc_tunnel_service.dart';

class ServerManager extends ChangeNotifier {
  HttpServer? _server;
  bool _isRunning = false;
  String _ipAddress = '127.0.0.1';
  int _port = 8080;
  String? _websiteFolder;
  DateTime? _startTime;

  final VisitorTracker visitorTracker;
  PreferencesService? _prefs;
  final WebRTCTunnelService tunnelService = WebRTCTunnelService();

  ServerManager(this.visitorTracker);

  Future<void> init(PreferencesService prefs) async {
    _prefs = prefs;
    _websiteFolder = _prefs?.getWebsiteFolder();
    notifyListeners();

    if (_websiteFolder != null && (_prefs?.getAutoStart() ?? false)) {
      try {
        await startServer();
      } catch (e) {
        print('Auto-start failed: $e');
      }
    }
  }

  bool get isRunning => _isRunning;
  bool get autoStart => _prefs?.getAutoStart() ?? false;
  bool get tunnelEnabled => _prefs?.getTunnelEnabled() ?? false;
  String get subdomain => _prefs?.getSubdomain() ?? '';
  String get tunnelToken {
    var token = _prefs?.getTunnelToken() ?? '';
    if (token.isEmpty) {
      token = DateTime.now().millisecondsSinceEpoch.toString() + '_' + _port.toString();
      _prefs?.setTunnelToken(token);
    }
    return token;
  }
  Duration get uptime => _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;
  String get ipAddress => _ipAddress;
  int get port => _port;
  String? get websiteFolder => _websiteFolder;

  void setWebsiteFolder(String path) {
    _websiteFolder = path;
    _prefs?.setWebsiteFolder(path);
    notifyListeners();
  }

  Future<void> setAutoStart(bool value) async {
    await _prefs?.setAutoStart(value);
    notifyListeners();
  }

  Future<void> setTunnelEnabled(bool value) async {
    await _prefs?.setTunnelEnabled(value);
    notifyListeners();
    // Restart tunnel if server is running
    if (_isRunning) {
      if (value) {
        if (subdomain.isNotEmpty) {
          await tunnelService.start(subdomain, tunnelToken, _port);
        }
      } else {
        tunnelService.stop();
      }
      notifyListeners();
    }
  }

  Future<void> setSubdomain(String value) async {
    await _prefs?.setSubdomain(value);
    notifyListeners();
    // Restart tunnel if running to update subdomain
    if (_isRunning && tunnelEnabled) {
      tunnelService.stop();
      if (value.isNotEmpty) {
        await tunnelService.start(value, tunnelToken, _port);
      }
      notifyListeners();
    }
  }

  Future<void> startServer() async {
    if (_isRunning) return;
    if (_websiteFolder == null) {
      throw Exception('Website folder not selected');
    }

    try {
      _ipAddress = await NetworkUtils.getLocalIpAddress();

      final staticHandler = createStaticHandler(
        _websiteFolder!,
        defaultDocument: 'index.html',
        serveFilesOutsidePath: true,
      );

      final handler = Pipeline()
          .addMiddleware(_trackingMiddleware())
          .addHandler(staticHandler);

      _server = await io.serve(handler, InternetAddress.anyIPv4, _port);
      _isRunning = true;
      _startTime = DateTime.now();
      visitorTracker.clearLogs();

      if (tunnelEnabled && subdomain.isNotEmpty) {
        await tunnelService.start(subdomain, tunnelToken, _port);
      }

      notifyListeners();
    } catch (e) {
      print('Failed to start server: $e');
      _isRunning = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopServer() async {
    if (!_isRunning || _server == null) return;

    tunnelService.stop();
    await _server!.close(force: true);
    _server = null;
    _isRunning = false;
    _startTime = null;
    notifyListeners();
  }

  Middleware _trackingMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final path = request.requestedUri.path;
        final method = request.method;

        // Simple visitor tracking: count requests to / or /index.html as a visit
        // A more robust implementation would use cookies or IP tracking
        if (path == '/' || path.toLowerCase().endsWith('index.html')) {
          visitorTracker.incrementVisitor();
        }

        visitorTracker.logRequest('$method $path');

        return Future.sync(() => innerHandler(request)).then((response) {
          return response;
        });
      };
    };
  }
}
