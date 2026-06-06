import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class CloudflareTunnelService {
  final String workerUrl = 'wss://odd-paper-88df.dtechxpreas.workers.dev/register';
  WebSocketChannel? _channel;
  bool _isConnected = false;
  int _localPort = 8080;

  bool get isConnected => _isConnected;

  Future<void> start(String subdomain, String token, int localPort) async {
    _localPort = localPort;
    final url = Uri.parse('$workerUrl?subdomain=$subdomain&token=$token');

    try {
      _channel = WebSocketChannel.connect(url);
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          _isConnected = false;
          debugPrint('WebSocket disconnected');
        },
        onError: (error) {
          _isConnected = false;
          debugPrint('WebSocket error: $error');
        },
      );
    } catch (e) {
      _isConnected = false;
      debugPrint('Failed to connect to Cloudflare Tunnel: $e');
    }
  }

  void stop() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  Future<void> _handleMessage(dynamic message) async {
    try {
      // Message format: "requestId|method|path|headersJSON|body"
      final parts = (message as String).split('|');
      if (parts.length < 4) return;

      final requestId = parts[0];
      final method = parts[1];
      final path = parts[2];
      final headersJson = parts[3];
      final body = parts.length > 4 ? parts.sublist(4).join('|') : null;

      final headers = Map<String, String>.from(jsonDecode(headersJson));

      // Remove host header to avoid issues with local server
      headers.remove('host');
      headers.remove('Host');

      final localUrl = Uri.parse('http://127.0.0.1:$_localPort$path');

      http.Response response;
      final req = http.Request(method, localUrl);
      req.headers.addAll(headers);
      if (body != null && body.isNotEmpty) {
        req.body = body;
      }

      final streamResponse = await req.send();
      response = await http.Response.fromStream(streamResponse);

      final responseHeadersJson = jsonEncode(response.headers);

      // Reply format: Send headers as text, then body as binary
      _channel?.sink.add('RES|$requestId|${response.statusCode}|$responseHeadersJson');

      if (response.bodyBytes.isNotEmpty) {
        // Send a separate binary message for the body
        // Format: requestId (bytes) + bodyBytes
        final idBytes = utf8.encode(requestId);
        final idLength = idBytes.length;

        final binaryMessage = BytesBuilder();
        binaryMessage.addByte(idLength); // 1 byte for ID length
        binaryMessage.add(idBytes); // The ID
        binaryMessage.add(response.bodyBytes); // The payload

        _channel?.sink.add(binaryMessage.takeBytes());
      } else {
        // Send an empty binary message so the worker knows we're done
        final idBytes = utf8.encode(requestId);
        final idLength = idBytes.length;

        final binaryMessage = BytesBuilder();
        binaryMessage.addByte(idLength);
        binaryMessage.add(idBytes);

        _channel?.sink.add(binaryMessage.takeBytes());
      }

    } catch (e) {
      // Avoid printing to console in production
      debugPrint('Error handling tunnel request: $e');
    }
  }
}
