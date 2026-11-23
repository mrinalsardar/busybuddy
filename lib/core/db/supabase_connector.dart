import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db_time.dart';

/// Connects the PowerSync database to Supabase: credentials come from the
/// Supabase session, and [uploadData] drains the local upload queue following
/// the client write contract in supabase/README.md:
///
/// - a new sale and its items upload as one `record_sale` call, which also
///   writes the sale's stock movements on the server;
/// - `stock_movement` rows upload as inserts that ignore an existing id, so a
///   retry never applies one twice;
/// - `stock_qty` is never uploaded: the server computes it from movements;
/// - a new shop uploads through `create_shop`, a profile change through
///   `update_profile`;
/// - other tables are upserted, updated and deleted directly.
///
/// Network and server errors are rethrown, so PowerSync retries the change
/// later. A change the server rejects for good (a SQLSTATE the README names,
/// see [isPermanentError]) would block every later change, sales included, so
/// it is recorded in the local `upload_error` table and skipped.
class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector(this.client, {required this.powerSyncUrl});

  final SupabaseClient client;

  /// PowerSync service endpoint.
  final String powerSyncUrl;

  /// Columns kept on the device but never uploaded, per table.
  static const _localColumns = {
    'product': {'stock_qty'},
    'product_variant': {'stock_qty'},
    'business_profile': {'google_account_id'},
  };

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    var session = client.auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      session = (await client.auth.refreshSession()).session;
      if (session == null) return null;
    }
    final expiresAt = session.expiresAt;
    return PowerSyncCredentials(
      endpoint: powerSyncUrl,
      token: session.accessToken,
      userId: session.user.id,
      expiresAt: expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // Without a session, requests run as anon, which the server refuses
    // (42501); that is not the change's fault, so keep the queue for later.
    if (client.auth.currentSession == null) {
      throw StateError('Not signed in; uploads wait for a Supabase session');
    }
    while (true) {
      final transaction = await database.getNextCrudTransaction();
      if (transaction == null) return;
      await _uploadTransaction(database, transaction.crud);
      await transaction.complete();
    }
  }

  Future<void> _uploadTransaction(PowerSyncDatabase database, List<CrudEntry> crud) async {
    // Sale items upload with their sale, in its record_sale call.
    final newSales = {
      for (final op in crud)
        if (op.table == 'sale' && op.op == UpdateType.put) op.id,
    };
    final itemsBySale = <String, List<CrudEntry>>{};
    for (final op in crud) {
      final saleId = op.opData?['sale_id'];
      if (op.table == 'sale_item' && op.op == UpdateType.put && newSales.contains(saleId)) {
        itemsBySale.putIfAbsent(saleId as String, () => []).add(op);
      }
    }

    for (final op in crud) {
      if (op.table == 'sale_item' && op.op == UpdateType.put && newSales.contains(op.opData?['sale_id'])) {
        continue;
      }
      final items = op.table == 'sale' && op.op == UpdateType.put ? itemsBySale[op.id] ?? const <CrudEntry>[] : null;
      try {
        await _uploadOp(op, items);
      } on PostgrestException catch (e) {
        if (!isPermanentError(e)) rethrow;
        await _recordFailure(database, [op, ...?items], e.code, e.message);
      } on _UnsupportedChange catch (e) {
        await _recordFailure(database, [op], null, e.message);
      }
    }
  }

  Future<void> _uploadOp(CrudEntry op, List<CrudEntry>? saleItems) async {
    final local = _localColumns[op.table] ?? const <String>{};
    final data = {
      for (final e in (op.opData ?? const <String, dynamic>{}).entries)
        if (!local.contains(e.key)) e.key: e.value,
    };
    final row = {...data, 'id': op.id};

    switch ((op.table, op.op)) {
      case ('business_profile', UpdateType.put):
        await client.rpc('create_shop', params: {'profile': row});
      case ('business_profile', UpdateType.patch):
        if (data.isEmpty) return;
        await client.rpc('update_profile', params: {'profile': row});
      case ('business_profile', UpdateType.delete):
        throw const _UnsupportedChange('A shop cannot be deleted');
      case ('sale', UpdateType.put):
        await client.rpc('record_sale', params: {
          'sale': row,
          'items': [for (final item in saleItems!) {...?item.opData, 'id': item.id}],
        });
      case ('sale_item', UpdateType.put):
        throw const _UnsupportedChange('A sale item uploads only with its new sale (record_sale)');
      case ('stock_movement', UpdateType.put):
        await client.from('stock_movement').upsert(
          {for (final e in row.entries) if (e.key != 'created_by' || e.value != null) e.key: e.value},
          onConflict: 'id',
          ignoreDuplicates: true,
        );
      case ('stock_movement', _):
        throw const _UnsupportedChange('Stock movements are never updated or deleted');
      case (_, UpdateType.put):
        await client.from(op.table).upsert(row);
      case (_, UpdateType.patch):
        if (data.isEmpty) return;
        await client.from(op.table).update(data).eq('id', op.id);
      case (_, UpdateType.delete):
        await client.from(op.table).delete().eq('id', op.id);
    }
  }

  Future<void> _recordFailure(PowerSyncDatabase database, List<CrudEntry> ops, String? code, String message) async {
    debugPrint('Upload rejected, skipped: ${ops.first.table} ${ops.first.id}: $code $message');
    final now = toDbTime(DateTime.now());
    await database.writeTransaction((tx) async {
      for (final op in ops) {
        await tx.execute(
          'INSERT INTO upload_error (id, table_name, op, row_id, data, code, message, created_at) '
          'VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?)',
          [op.table, op.op.toJson(), op.id, jsonEncode(op.opData), code, message, now],
        );
      }
    });
  }

  /// Whether the server rejected a change for good, so retrying cannot help.
  /// These are the SQLSTATE classes the server functions use (see
  /// supabase/README.md, "Server functions"): 42501 (not a member/owner),
  /// class 22 (bad argument, e.g. 22023) and class 23 (constraint, e.g.
  /// 23514 currency locked or CHECK, 23505 unique, 23503 foreign key).
  /// Anything else, such as a timeout or an expired token, is retried.
  static bool isPermanentError(PostgrestException e) {
    final code = e.code ?? '';
    return code == '42501' || code.startsWith('22') || code.startsWith('23');
  }
}

/// A local change the server contract has no way to upload.
class _UnsupportedChange implements Exception {
  final String message;
  const _UnsupportedChange(this.message);
}
