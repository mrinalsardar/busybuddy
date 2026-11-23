import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:busybuddy/core/db/database_helper.dart';

/// Opens the app's PowerSync database on a temporary file (no server) for the
/// tests of one file, and deletes it afterwards. Call from `main`.
void useTestDatabase() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('busybuddy_test');
    await DatabaseHelper().open(path: '${dir.path}/test.db');
  });

  // Every test starts from an empty database and upload queue.
  setUp(() => DatabaseHelper().deleteDb());

  tearDownAll(() async {
    await DatabaseHelper().close();
    await dir.delete(recursive: true);
  });
}
