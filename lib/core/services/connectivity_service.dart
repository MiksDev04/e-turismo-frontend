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
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
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

  // Only one check runs at a time. Without this, the periodic timer, the
  // connectivity_plus listener and callers of `checkOnline` all start their own
  // lookups, which pile up whenever the network is slow.
  Future<void>? _inFlight;

  Future<void> _check() => _inFlight ??= _runCheck().whenComplete(() => _inFlight = null);

  Future<void> _runCheck() async {
    bool online;
    if (kIsWeb) {
      final results = await _connectivity.checkConnectivity();
      online = results.any((r) => r != ConnectivityResult.none);
    } else {
      online = await _hasInternet();
    }

    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(_isOnline);
      debugPrint('🌐 ConnectivityService: changed to isOnline = $_isOnline');
    }
  }

  /// "Online" means the device can reach the internet. Whether the backend
  /// itself is up is handled separately by [classifyError] (500 vs 503).
  Future<bool> _hasInternet() async {
    // 1. Fast exit: no network interface at all.
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.every((r) => r == ConnectivityResult.none)) return false;
    } catch (_) {
      // Fall through to the active probes.
    }

    // 2. Race raw-socket probes (no DNS involved) against a DNS lookup of the
    //    backend host. First success wins, so a slow/broken DNS resolver no
    //    longer makes a working connection look offline.
    final online = await _anySucceeds([
      () => _canConnect('1.1.1.1', 443),
      () => _canConnect('8.8.8.8', 443),
      _canResolveBackend,
    ]);

    if (!online) debugPrint('🌐 Connectivity check failed: all probes failed');
    return online;
  }

  Future<bool> _canConnect(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 4));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canResolveBackend() async {
    try {
      final result = await InternetAddress.lookup(_checkHost)
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('🌐 DNS lookup for $_checkHost failed: $e');
      return false;
    }
  }

  Future<bool> _anySucceeds(List<Future<bool> Function()> probes) {
    final completer = Completer<bool>();
    var pending = probes.length;
    for (final probe in probes) {
      probe().then((ok) {
        if (ok && !completer.isCompleted) completer.complete(true);
      }).catchError((_) {}).whenComplete(() {
        if (--pending == 0 && !completer.isCompleted) completer.complete(false);
      });
    }
    return completer.future;
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