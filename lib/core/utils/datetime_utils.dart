final RegExp _dbDatePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?',
);

/// Parses a naive MySQL date/datetime string returned by the backend
/// ('YYYY-MM-DD' or 'YYYY-MM-DD HH:mm:ss') as wall-clock time in the app's
/// canonical timezone (Asia/Manila). The returned [DateTime] carries the exact
/// components from the string, so display formatting and day arithmetic never
/// depend on the device timezone. Any trailing timezone marker on the string
/// is ignored on purpose: the wall-clock components are already canonical.
/// Falls back to [DateTime.parse] for strings that do not match the DB format.
DateTime parseDbDateTime(String value) {
  final m = _dbDatePattern.firstMatch(value.trim());
  if (m != null) {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      m.group(4) != null ? int.parse(m.group(4)!) : 0,
      m.group(5) != null ? int.parse(m.group(5)!) : 0,
      m.group(6) != null ? int.parse(m.group(6)!) : 0,
    );
  }
  return DateTime.parse(value);
}

/// Same as [parseDbDateTime] but returns null for null, empty, or
/// unparseable input.
DateTime? tryParseDbDateTime(String? value) {
  if (value == null) return null;
  final s = value.trim();
  if (s.isEmpty) return null;
  try {
    return parseDbDateTime(s);
  } catch (_) {
    return null;
  }
}
