import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
//  ConnectivityService (Unified)
//
//  Wraps connectivity_plus and performs an active reachability check against
//  the app's own backend to verify actual internet + server connectivity.
// ─────────────────────────────────────────────────────────────────────────────

class ConnectivityService {
  ConnectivityService._internal();
  static final ConnectivityService instance = ConnectivityService._internal();

  final _connectivity = Connectivity();
  bool _isOnline = false;

  /// Current cached connectivity status.
  bool get isOnline => _isOnline;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  /// Stream of connectivity changes (true = online, false = offline).
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Alias for onConnectivityChanged to support legacy code.
  Stream<bool> get onlineStream => onConnectivityChanged;

  Timer? _timer;
  StreamSubscription? _subscription;

  /// The host to check reachability against — your own backend, not a
  /// third-party domain, so the check reflects what the app actually needs.
  String get _checkHost {
    final url = defaultTargetPlatform == TargetPlatform.android
        ? (dotenv.env['ANDROID_BACKEND_URL'] ?? 'https://e-turismo-backend-main.onrender.com')
        : (dotenv.env['BACKEND_URL'] ?? 'https://e-turismo-backend-main.onrender.com');
    return Uri.parse(url).host;
  }

  /// Starts monitoring connectivity changes.
  Future<void> startWatching() async {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _check();
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    await _check();
  }

  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _controller.close();
  }

  /// One-time snapshot — await this for a fresh, verified check.
  Future<bool> get checkOnline async {
    await _check();
    return _isOnline;
  }

  /// Legacy support for Future<bool> isOnline
  Future<bool> get isOnlineAsync async {
    return await checkOnline;
  }

  Future<void> _check() async {
    bool online;
    if (kIsWeb) {
      final results = await _connectivity.checkConnectivity();
      online = results.any((r) => r != ConnectivityResult.none);
    } else {
      try {
        final result = await InternetAddress.lookup(_checkHost)
            .timeout(const Duration(seconds: 5));
        online = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      } catch (e) {
        debugPrint('🌐 Connectivity check failed: $e');
        online = false;
      }
    }

    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(_isOnline);
      debugPrint('🌐 ConnectivityService: changed to isOnline = $_isOnline');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  isNetworkError
// ─────────────────────────────────────────────────────────────────────────────

/// Classifies a network/API error into the appropriate HTTP status code.
///
/// Uses a real device connectivity check ([ConnectivityService.isOnlineAsync])
/// to distinguish actual offline (503) from server-unreachable (500) and
/// timeout (408).
Future<int> classifyError(dynamic error) async {
  if (error is TimeoutException) return 408;
  if (!isNetworkError(error)) return 500;
  final online = await ConnectivityService.instance.isOnlineAsync;
  return online ? 500 : 503;
}

bool isNetworkError(dynamic error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is http.ClientException) return true;
  final s = error.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('no address associated') ||
      s.contains('network error') ||
      s.contains('connection failed') ||
      s.contains('timed out');
}