/// "1 item", "2 items". [plural] defaults to [singular] + "s".
String countLabel(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';
