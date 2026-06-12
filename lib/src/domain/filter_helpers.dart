final _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? parseFilterStartDate(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return DateTime.tryParse(trimmed);
}

DateTime? parseFilterEndDate(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) {
    return null;
  }
  if (_dateOnlyPattern.hasMatch(trimmed)) {
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      23,
      59,
      59,
      999,
      999,
    );
  }
  return parsed;
}

bool matchesFilterText(String value, String? filter) {
  if (filter == null || filter.trim().isEmpty) {
    return true;
  }
  return value.trim().toLowerCase() == filter.trim().toLowerCase();
}
