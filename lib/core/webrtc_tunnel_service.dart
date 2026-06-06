import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

class WebRTCTunnelService {
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};

  bool _isConnected = false;
  int _localPort = 8080;
  String? _subdomain;

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  bool get isConnected => _isConnected;

  Future<void> start(String subdomain, String token, int localPort) async {
    _localPort = localPort;
    _subdomain = subdomain;
    _isConnected = true; // True indicates we are actively listening for visitors

    // Listen for incoming connection requests (Offers) from visitors
    _db.child('signaling/$_subdomain/requests').onChildAdded.listen((event) {
      if (event.snapshot.value != null) {
        _handleIncomingRequest(event.snapshot.key!, Map<String, dynamic>.from(event.snapshot.value as Map));
      }
    });
  }

  void stop() {
    _isConnected = false;
    _peerConnections.forEach((key, pc) {
      pc.close();
    });
    _peerConnections.clear();
    _dataChannels.clear();

    if (_subdomain != null) {
       _db.child('signaling/$_subdomain').remove();
    }
  }

  Future<void> _handleIncomingRequest(String requestId, Map<String, dynamic> data) async {
    try {
      final offerData = Map<String, dynamic>.from(data['offer'] as Map);

      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'}
        ]
      };

      final pc = await createPeerConnection(configuration);
      _peerConnections[requestId] = pc;

      // When the browser creates the DataChannel, we get it here
      pc.onDataChannel = (RTCDataChannel channel) {
        _dataChannels[requestId] = channel;

        channel.onMessage = (RTCDataChannelMessage message) {
           if (!message.isBinary) {
             _handleMessage(message.text, channel);
           }
        };

        channel.onDataChannelState = (RTCDataChannelState state) {
           if (state == RTCDataChannelState.RTCDataChannelClosed) {
             _dataChannels.remove(requestId);
             _peerConnections[requestId]?.close();
             _peerConnections.remove(requestId);
             _db.child('signaling/$_subdomain/requests/$requestId').remove();
           }
        };
      };

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        _db.child('signaling/$_subdomain/candidates/$requestId/phone').push().set({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      // Listen for browser ICE candidates
      _db.child('signaling/$_subdomain/candidates/$requestId/visitor').onChildAdded.listen((event) {
         if (event.snapshot.value != null) {
            final candidateData = Map<String, dynamic>.from(event.snapshot.value as Map);
            pc.addCandidate(RTCIceCandidate(
              candidateData['candidate'],
              candidateData['sdpMid'],
              candidateData['sdpMLineIndex']
            ));
         }
      });

      // Set Remote Description (The browser's offer)
      final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
      await pc.setRemoteDescription(offer);

      // Create Answer
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      // Send Answer back via Firebase
      await _db.child('signaling/$_subdomain/answers/$requestId').set({
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp
        }
      });

    } catch (e) {
      debugPrint('Error handling WebRTC request: $e');
    }
  }

  Future<void> _handleMessage(String message, RTCDataChannel channel) async {
    try {
      // Message format: "requestId|method|path|headersJSON|body"
      final parts = message.split('|');
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
        req.bodyBytes = base64Decode(body);
      }

      final streamResponse = await req.send();
      response = await http.Response.fromStream(streamResponse);

      final responseHeadersJson = jsonEncode(response.headers);

      // Reply format: Send headers as text, then body as chunked binary
      channel.send(RTCDataChannelMessage('RES|$requestId|${response.statusCode}|$responseHeadersJson'));

      final idBytes = utf8.encode(requestId);
      final idLength = idBytes.length;

      if (response.bodyBytes.isNotEmpty) {
        const chunkSize = 64 * 1024; // 64KB max per message for WebRTC
        final totalBytes = response.bodyBytes.length;
        int offset = 0;

        while (offset < totalBytes) {
          final end = (offset + chunkSize < totalBytes) ? offset + chunkSize : totalBytes;
          final chunk = response.bodyBytes.sublist(offset, end);
          final isLast = end == totalBytes;

          final binaryMessage = BytesBuilder();
          // Header: 1 byte for ID length, 1 byte for flags (0 = more chunks, 1 = last chunk)
          binaryMessage.addByte(idLength);
          binaryMessage.addByte(isLast ? 1 : 0);
          binaryMessage.add(idBytes);
          binaryMessage.add(chunk);

          channel.send(RTCDataChannelMessage.fromBinary(binaryMessage.takeBytes()));
          offset = end;
        }
      } else {
        final binaryMessage = BytesBuilder();
        binaryMessage.addByte(idLength);
        binaryMessage.addByte(1); // 1 = last chunk (and only chunk)
        binaryMessage.add(idBytes);

        channel.send(RTCDataChannelMessage.fromBinary(binaryMessage.takeBytes()));
      }

    } catch (e) {
      debugPrint('Error handling tunnel request: $e');
    }
  }
}
