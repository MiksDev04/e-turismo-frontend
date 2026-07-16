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
