import 'package:shared_preferences/shared_preferences.dart';
import 'base_api.dart';

class AdminSetupStatus {
  const AdminSetupStatus({
    required this.setupAvailable,
    required this.adminExists,
  });

  final bool setupAvailable;
  final bool adminExists;

  factory AdminSetupStatus.fromJson(Map<String, dynamic> json) {
    return AdminSetupStatus(
      setupAvailable: json['setupAvailable'] == true,
      adminExists: json['adminExists'] == true,
    );
  }
}

class AdminSetupApi extends BaseApi {
  static const _cacheKey = 'admin_setup_complete';

  static Future<void> setAdminExists(bool exists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cacheKey, exists);
  }

  static Future<bool> isCachedAdminExists() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cacheKey) ?? false;
  }

  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  Future<AdminSetupStatus> getStatus() async {
    final response = await get('/api/auth/admin-setup/status');
    final data = handleResponse(response) as Map<String, dynamic>;
    return AdminSetupStatus.fromJson(data);
  }

  Future<String> requestAdminSetup({
    required String fullName,
    required String username,
    required String email,
    required String phoneNumber,
    required String password,
  }) async {
    final response = await post('/api/auth/admin-setup/request', {
      'fullName': fullName,
      'username': username,
      'email': email,
      'phoneNumber': phoneNumber,
      'password': password,
    });
    final data = handleResponse(response) as Map<String, dynamic>;
    return data['message']?.toString() ?? 'Confirmation email sent.';
  }
}
