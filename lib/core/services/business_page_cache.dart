// In-memory cache for business pages.
// Pages load once and reuse cached data until explicitly invalidated
// (after a mutation) or when the user triggers a manual refresh.

class BusinessPageCacheService {
  factory BusinessPageCacheService() => _instance;
  BusinessPageCacheService._();
  static final _instance = BusinessPageCacheService._();

  final Map<String, dynamic> _cache = {};

  bool hasData(String key) => _cache.containsKey(key);

  T? get<T>(String key) => _cache[key] as T?;

  void set(String key, dynamic data) => _cache[key] = data;

  void invalidate(String key) => _cache.remove(key);

  void invalidateAll() => _cache.clear();
}

class BusinessPageCacheKeys {
  BusinessPageCacheKeys._();

  static const dashboardDash = 'business_dashboard_dash';
  static const dashboardTrend = 'business_dashboard_trend';
  static const rooms = 'business_rooms';
  static const guestRecords = 'business_guest_records';
  static const messages = 'business_messages';
  static const profile = 'business_profile';
}
