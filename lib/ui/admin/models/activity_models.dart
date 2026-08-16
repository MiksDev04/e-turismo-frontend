// lib/ui/admin/models/activity_models.dart

/// Aggregated activity level for an accommodation or attraction, derived from
/// its most recent guest / visit record.
enum ActivityStatus { active, lowActivity, inactive, noActivity }

/// Maps a raw DB value to [ActivityStatus]. Unknown or empty values default to
/// [ActivityStatus.noActivity].
ActivityStatus parseActivityStatus(String? raw) {
  switch (raw) {
    case 'active':
      return ActivityStatus.active;
    case 'low_activity':
      return ActivityStatus.lowActivity;
    case 'inactive':
      return ActivityStatus.inactive;
    case 'no_activity':
    default:
      return ActivityStatus.noActivity;
  }
}
