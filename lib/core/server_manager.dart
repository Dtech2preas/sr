import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'visitor_tracker.dart';
import 'network_utils.dart';

class ServerManager extends ChangeNotifier {
  HttpServer? _server;
  bool _isRunning = false;
  String _ipAddress = '127.0.0.1';
  int _port = 8080;
  String? _websiteFolder;

  final VisitorTracker visitorTracker;

  ServerManager(this.visitorTracker);

  bool get isRunning => _isRunning;
  String get ipAddress => _ipAddress;
  int get port => _port;
  String? get websiteFolder => _websiteFolder;

  void setWebsiteFolder(String path) {
    _websiteFolder = path;
    notifyListeners();
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
      visitorTracker.clearLogs();
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

    await _server!.close(force: true);
    _server = null;
    _isRunning = false;
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
