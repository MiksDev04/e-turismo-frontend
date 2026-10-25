class ActivityLog {
  final String id;
  final DateTime createdAt;
  final String actionType;
  final String? details;
  final String? actorId;
  final String? actorName;
  final String? actorRole;
  final String? actorOrgName;
  final String? targetName;

  const ActivityLog({
    required this.id,
    required this.createdAt,
    required this.actionType,
    this.details,
    this.actorId,
    this.actorName,
    this.actorRole,
    this.actorOrgName,
    this.targetName,
  });

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      id: json['id']?.toString() ?? '',
      createdAt: DateTime.parse(json['created_at'].toString()),
      actionType: json['action_type']?.toString() ?? '',
      details: json['details']?.toString(),
      actorId: json['actor_id']?.toString(),
      actorName: json['actor_name']?.toString(),
      actorRole: json['actor_role']?.toString(),
      actorOrgName: json['actor_org_name']?.toString(),
      targetName: json['target_name']?.toString(),
    );
  }
}

class ActivityLogResponse {
  final List<ActivityLog> items;
  final int total;
  final int page;
  final int limit;

  const ActivityLogResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory ActivityLogResponse.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List? ?? [])
        .map((e) => ActivityLog.fromJson(e as Map<String, dynamic>))
        .toList();
    return ActivityLogResponse(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
    );
  }
}
