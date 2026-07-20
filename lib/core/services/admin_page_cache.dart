// In-memory cache for admin pages.
// Pages load once and reuse cached data until explicitly invalidated
// (after a mutation) or when the user triggers a manual refresh.

class AdminPageCacheService {
  factory AdminPageCacheService() => _instance;
  AdminPageCacheService._();
  static final _instance = AdminPageCacheService._();

  final Map<String, dynamic> _cache = {};

  bool hasData(String key) => _cache.containsKey(key);

  T? get<T>(String key) => _cache[key] as T?;

  void set(String key, dynamic data) => _cache[key] = data;

  void invalidate(String key) => _cache.remove(key);

  void invalidateAll() => _cache.clear();
}

class AdminPageCacheKeys {
  AdminPageCacheKeys._();

  static const dashboardDash = 'admin_dashboard_dash';
  static const dashboardTrend = 'admin_dashboard_trend';
  static const accommodations = 'admin_accommodations';
  static const messages = 'admin_messages';
  static const reports = 'admin_reports';
  static const compliance = 'admin_compliance';
  static const profile = 'admin_profile';
}
