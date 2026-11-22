/// Timestamps are stored as UTC ISO-8601 text with millisecond precision
/// ("2026-11-10T08:30:00.123Z"), from Dart and from the SQL column defaults
/// alike, so they sort and compare correctly as strings.
library;

/// SQL column default that matches [toDbTime].
const sqlNow = "(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))";

String toDbTime(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true)
        .toIso8601String();

/// Parses a stored timestamp into local time.
DateTime? fromDbTime(Object? value) =>
    value == null ? null : DateTime.tryParse(value as String)?.toLocal();

/// Calendar dates (expiry date, expense date) are stored as "YYYY-MM-DD",
/// with no time zone, so the day never shifts.
String toDbDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? fromDbDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value as String);
