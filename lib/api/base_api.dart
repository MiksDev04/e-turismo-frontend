import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import '../core/services/session_service.dart';

class BaseApi {
  static const _timeout = Duration(seconds: 30);
  static final http.Client _client = http.Client();

  String get baseUrl {
    if (kIsWeb) {
      return const String.fromEnvironment(
        'BACKEND_URL',
        defaultValue: 'http://localhost:3000',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return dotenv.env['ANDROID_BACKEND_URL'] ?? 'http://10.0.2.2:3000';
    }
    return dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
  }

  String? get apiKey {
    if (kIsWeb) {
      return const String.fromEnvironment('API_KEY');
    }
    return dotenv.env['API_KEY'];
  }

  Map<String, String> get headers {
    final Map<String, String> h = {
      'Content-Type': 'application/json',
      'x-api-key': apiKey ?? '',
    };
    
    final token = SessionService.instance.current?.token;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    
    return h;
  }

  bool get hasToken {
    final token = SessionService.instance.current?.token;
    return token != null && token.isNotEmpty;
  }

  // ── Background re-auth gate ────────────────────────────────────────────────
  //
  // The app re-logs-in silently in several places (expired token, sync, app
  // resume, offline→online). Every one of those hits POST /api/auth/login and
  // is charged to the same rate-limit bucket as the user's manual login. To
  // stop that from producing "Too many attempts" on a first visible attempt:
  //   • concurrent 401s share a single login request (single-flight), and
  //   • after a refusal (401/403/429) we back off for the server's 15-minute
  //     window instead of retrying and burning more attempts.
  static Future<Map<String, dynamic>?>? _reauthInFlight;
  static DateTime? _reauthBlockedUntil;

  /// Clears the back-off state. Call after a successful manual login.
  static void resetReauthGate() {
    _reauthBlockedUntil = null;
  }

  /// Re-authenticates using the credentials cached in the session.
  /// Returns the parsed login response, or null if it could not re-auth.
  Future<Map<String, dynamic>?> reauthenticate() {
    final session = SessionService.instance.current;
    final username = session?.username;
    final password = session?.password;
    if (username == null || password == null) return Future.value(null);
    return guardedLogin(username: username, password: password);
  }

  /// Single-flight, back-off aware login used by background re-auth.
  Future<Map<String, dynamic>?> guardedLogin({
    required String username,
    required String password,
  }) {
    final existing = _reauthInFlight;
    if (existing != null) return existing;

    late final Future<Map<String, dynamic>?> future;
    future = _performLogin(username, password).whenComplete(() {
      if (identical(_reauthInFlight, future)) _reauthInFlight = null;
    });
    _reauthInFlight = future;
    return future;
  }

  Future<Map<String, dynamic>?> _performLogin(
    String username,
    String password,
  ) async {
    final blockedUntil = _reauthBlockedUntil;
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
      debugPrint('⏳ Background re-auth skipped — backing off until $blockedUntil');
      return null;
    }

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey ?? '',
        },
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        _reauthBlockedUntil = null;
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      // Retrying cannot help: bad credentials, account not allowed, or the
      // server is already rate-limiting this username.
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 429) {
        _reauthBlockedUntil = DateTime.now().add(const Duration(minutes: 15));
      } else {
        _reauthBlockedUntil = DateTime.now().add(const Duration(seconds: 60));
      }
      debugPrint('⚠️ Background re-auth refused: ${response.statusCode}');
    } catch (e) {
      _reauthBlockedUntil = DateTime.now().add(const Duration(seconds: 60));
      debugPrint('⚠️ Background re-auth failed: $e');
    }
    return null;
  }

  Future<bool> _attemptReauth() async {
    final data = await reauthenticate();
    if (data == null) return false;

    final session = SessionService.instance.current;
    if (session == null) return false;

    final token = data['token'];
    final updated = session.copyWith(token: token, isOfflineSession: false);
    await SessionService.instance.save(updated);
    await SessionService.instance.loadAndCache();
    return true;
  }

  Future<http.Response> get(String endpoint, {Duration? timeout}) async {
    final t = timeout ?? _timeout;
    var response = await _client.get(Uri.parse('$baseUrl$endpoint'), headers: headers).timeout(t);
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await _client.get(Uri.parse('$baseUrl$endpoint'), headers: headers).timeout(t);
      }
    }
    return response;
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    var response = await _client.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await _client.post(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(body),
        ).timeout(_timeout);
      }
    }
    return response;
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    var response = await _client.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await _client.put(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(body),
        ).timeout(_timeout);
      }
    }
    return response;
  }

  Future<http.Response> delete(String endpoint) async {
    var response = await _client.delete(Uri.parse('$baseUrl$endpoint'), headers: headers).timeout(_timeout);
    if (response.statusCode == 401 && endpoint != '/api/auth/login') {
      if (await _attemptReauth()) {
        response = await _client.delete(Uri.parse('$baseUrl$endpoint'), headers: headers).timeout(_timeout);
      }
    }
    return response;
  }

  dynamic handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'An error occurred';
      try {
        final body = jsonDecode(response.body);
        message = body['message'] ?? message;
      } catch (_) {}
      
      if (response.statusCode == 401) {
        final session = SessionService.instance.current;
        final isBusiness = session?.role == 'business';
        final isOfflineSession = session?.isOfflineSession ?? false;

        if (isBusiness || isOfflineSession) {
          debugPrint('⚠️ Unauthorized (401) but business/offline session active. Skipping session clear.');
        } else {
          debugPrint('⚠️ Unauthorized (401): $message. Clearing session.');
          SessionService.instance.clear();
        }
      }
      
      throw ApiException(message, response.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}