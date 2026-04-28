import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// ══════════════════════════════════════════════════════════════════════
///  WebSocket Server Service — Real Auto-Save Interceptor
///
///  Runs a local WebSocket server on ws://localhost:2050
///  Listens for credential payloads from the Chrome Extension
///  via Native Messaging Bridge.
///
///  Protocol:
///  → Chrome Extension sends:
///    {"type":"NEW_LOGIN", "url":"...", "username":"...", "password":"..."}
///  ← Server responds:
///    {"status":"received","timestamp":"..."}
///
///  Runs continuously in the background, even when app is in system tray.
/// ══════════════════════════════════════════════════════════════════════

typedef OnCredentialIntercepted = void Function(
  String url,
  String username,
  String password,
);

class WebSocketServerService {
  HttpServer? _server;
  final List<WebSocket> _connectedClients = [];
  OnCredentialIntercepted? onCredentialIntercepted;
  bool _isRunning = false;

  static const int _port = 2050;
  static const String _host = '127.0.0.1';

  bool get isRunning => _isRunning;
  int get connectedClients => _connectedClients.length;

  /// Start the WebSocket server on ws://localhost:2050
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('[🔌 WebSocket] Server already running on $_host:$_port');
      return;
    }

    try {
      _server = await HttpServer.bind(_host, _port, shared: true);
      _isRunning = true;
      debugPrint(
          '[🔌 WebSocket] Server started on ws://$_host:$_port');

      _server!.listen(
        _handleHttpRequest,
        onError: (error) {
          debugPrint('[🔌 WebSocket] Server error: $error');
        },
        onDone: () {
          debugPrint('[🔌 WebSocket] Server stopped.');
          _isRunning = false;
        },
      );
    } catch (e) {
      debugPrint('[🔌 WebSocket] Failed to start server: $e');
      _isRunning = false;
    }
  }

  /// Handle incoming HTTP request — upgrade to WebSocket if applicable
  Future<void> _handleHttpRequest(HttpRequest request) async {
    // ── Health check endpoint (GET /) ──
    if (request.method == 'GET' &&
        request.uri.path == '/' &&
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'service': 'Mahfadha Pro Auto-Save Interceptor',
          'status': 'running',
          'websocket': 'ws://$_host:$_port',
          'clients': _connectedClients.length,
        }));
      await request.response.close();
      return;
    }

    // ── CORS preflight ──
    if (request.method == 'OPTIONS') {
      _addCorsHeaders(request.response);
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // ── WebSocket upgrade ──
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _onClientConnected(socket);
      } catch (e) {
        debugPrint('[🔌 WebSocket] Upgrade failed: $e');
      }
      return;
    }

    // ── POST fallback for non-WebSocket clients (e.g. TCP socket) ──
    if (request.method == 'POST') {
      _addCorsHeaders(request.response);
      try {
        final body = await utf8.decoder.bind(request).join();
        _processPayload(body);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'received'}));
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'status': 'error', 'message': '$e'}));
      }
      await request.response.close();
      return;
    }

    // ── 404 for anything else ──
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  /// Handle new WebSocket client connection
  void _onClientConnected(WebSocket socket) {
    _connectedClients.add(socket);
    debugPrint(
        '[🔌 WebSocket] Client connected. Total: ${_connectedClients.length}');

    // Send welcome
    socket.add(jsonEncode({
      'type': 'WELCOME',
      'message': 'Connected to Mahfadha Pro Interceptor',
      'timestamp': DateTime.now().toIso8601String(),
    }));

    socket.listen(
      (data) {
        if (data is String) {
          _processPayload(data);
          // Acknowledge
          socket.add(jsonEncode({
            'status': 'received',
            'timestamp': DateTime.now().toIso8601String(),
          }));
        }
      },
      onError: (error) {
        debugPrint('[🔌 WebSocket] Client error: $error');
        _removeClient(socket);
      },
      onDone: () {
        _removeClient(socket);
      },
    );
  }

  /// Process incoming credential payload
  void _processPayload(String rawPayload) {
    try {
      final payload = rawPayload.trim();
      if (payload.isEmpty) return;

      final json = jsonDecode(payload) as Map<String, dynamic>;
      final type = json['type']?.toString() ?? '';

      if (type == 'NEW_LOGIN' || type == 'CREDENTIAL') {
        final url = json['url']?.toString() ?? '';
        final username = json['username']?.toString() ?? '';
        final password = json['password']?.toString() ?? '';

        if (url.isNotEmpty && username.isNotEmpty && password.isNotEmpty) {
          debugPrint(
              '[🔌 WebSocket] Intercepted credential for: $url');
          onCredentialIntercepted?.call(url, username, password);
        }
      }
    } catch (e) {
      debugPrint('[🔌 WebSocket] Payload parse error: $e');
    }
  }

  /// Remove disconnected client
  void _removeClient(WebSocket socket) {
    _connectedClients.remove(socket);
    debugPrint(
        '[🔌 WebSocket] Client disconnected. Remaining: ${_connectedClients.length}');
  }

  /// Add CORS headers for browser extension compatibility
  void _addCorsHeaders(HttpResponse response) {
    response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..add('Access-Control-Allow-Headers', 'Content-Type');
  }

  /// Broadcast a message to all connected WebSocket clients
  void broadcast(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final client in List.from(_connectedClients)) {
      try {
        client.add(encoded);
      } catch (_) {
        _removeClient(client);
      }
    }
  }

  /// Stop the server and close all connections
  Future<void> stop() async {
    for (final client in List.from(_connectedClients)) {
      try {
        await client.close();
      } catch (_) {}
    }
    _connectedClients.clear();

    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    debugPrint('[🔌 WebSocket] Server stopped and all clients disconnected.');
  }
}
