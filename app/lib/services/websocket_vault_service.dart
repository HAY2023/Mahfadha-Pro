import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class WebsocketVaultService {
  HttpServer? _server;
  WebSocket? _browserSocket;
  bool _isRunning = false;

  static const int _port = 8765;
  static const String _host = '127.0.0.1';

  Future<void> start() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(_host, _port, shared: true);
      _isRunning = true;
      debugPrint('[Autofill WS] Server started on ws://$_host:$_port');

      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _browserSocket = socket;
          debugPrint('[Autofill WS] Browser extension connected.');

          socket.listen(
            (data) {},
            onDone: () {
              debugPrint('[Autofill WS] Browser extension disconnected.');
              if (_browserSocket == socket) _browserSocket = null;
            },
            onError: (err) {
              debugPrint('[Autofill WS] Socket error: $err');
              if (_browserSocket == socket) _browserSocket = null;
            },
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      debugPrint('[Autofill WS] Failed to start server: $e');
      _isRunning = false;
    }
  }

  void sendCredentialsToBrowser(String username, String password) {
    if (_browserSocket == null) {
      debugPrint('[Autofill WS] Cannot send credentials: No browser connected.');
      return;
    }

    final payload = jsonEncode({
      'action': 'inject',
      'username': username,
      'password': password,
    });

    _browserSocket!.add(payload);
    debugPrint('[Autofill WS] Credentials sent to browser extension.');
  }

  Future<void> stop() async {
    await _browserSocket?.close();
    _browserSocket = null;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
  }
}
