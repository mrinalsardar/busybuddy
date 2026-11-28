import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_helper.dart';

/// Keeps a provider that reads the database up to date: it re-runs when rows of
/// [tables] change, whether a sync or this app wrote them. A sync that writes
/// none of them does nothing.
///
/// The re-run is a refresh, so the previous value stays available and
/// `AsyncValue.when` keeps showing it instead of a loading state. For that, a
/// provider must also not `watch` anything that changes more often than its
/// query does (watch the shop's id, not the whole profile).
///
/// Call before the provider's first `await`, so no change is missed between
/// the subscription and the read.
void watchTables(Ref ref, Set<String> tables) {
  StreamSubscription<Object?>? subscription;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    subscription?.cancel();
  });
  DatabaseHelper().database.then((db) {
    if (disposed) return;
    subscription = db.onChange(tables, triggerImmediately: false).listen((_) => ref.invalidateSelf());
  }, onError: (Object _) {
    // The provider's own read reports a database that cannot open.
  });
}
