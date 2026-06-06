import 'package:flutter/foundation.dart';

class VisitorTracker extends ChangeNotifier {
  int _visitorCount = 0;
  final List<String> _recentRequests = [];

  int get visitorCount => _visitorCount;
  List<String> get recentRequests => List.unmodifiable(_recentRequests);

  void incrementVisitor() {
    _visitorCount++;
    notifyListeners();
  }

  void logRequest(String request) {
    // Keep only the last 50 requests
    if (_recentRequests.length >= 50) {
      _recentRequests.removeAt(0);
    }
    _recentRequests.add(request);
    notifyListeners();
  }

  void clearLogs() {
    _recentRequests.clear();
    _visitorCount = 0;
    notifyListeners();
  }
}
