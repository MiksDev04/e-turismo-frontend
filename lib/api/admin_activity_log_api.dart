import '../ui/admin/models/activity_log_model.dart';
import 'base_api.dart';

class AdminActivityLogApi extends BaseApi {
  Future<ActivityLogResponse> fetchActivityLogs({
    int page = 1,
    int limit = 20,
    String? actionType,
    String? dateFrom,
    String? dateTo,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (actionType != null && actionType.isNotEmpty) {
      queryParams['action_type'] = actionType;
    }
    if (dateFrom != null && dateFrom.isNotEmpty) {
      queryParams['date_from'] = dateFrom;
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      queryParams['date_to'] = dateTo;
    }

    final uri = Uri(path: '/api/admin/activity-logs', queryParameters: queryParams);
    final response = await get(uri.toString());
    final data = handleResponse(response);
    return ActivityLogResponse.fromJson(data as Map<String, dynamic>);
  }
}
