/// Errors raised by the DAOs for rules the local database no longer enforces.
///
/// The local database is PowerSync's SQLite copy, whose tables are views
/// without constraints, so the DAOs check these rules themselves before
/// writing. Nothing is written when one is thrown.
library;

abstract class DataException implements Exception {
  final String message;
  const DataException(this.message);

  @override
  String toString() => message;
}

/// A value breaks a rule of the schema, e.g. a negative price or a quantity
/// of 0. Mirrors the server's CHECK constraints.
class DataValidationException extends DataException {
  const DataValidationException(super.message);
}

/// An insert used an id that already exists in the table.
class DuplicateIdException extends DataException {
  DuplicateIdException(String table, Object? id) : super('$table $id already exists');
}

/// Another active product of the same shop already has this SKU or barcode.
///
/// This is a local check for instant feedback. Devices that were offline can
/// still create duplicates; the server accepts them and flags them in
/// `code_conflict` for the owner.
class DuplicateCodeException extends DataException {
  /// `sku` or `barcode`.
  final String field;
  final String value;

  DuplicateCodeException(this.field, this.value)
      : super('Another product already uses ${field == 'sku' ? 'SKU' : 'barcode'} $value');
}

/// A row cannot be deleted because other rows reference it, e.g. a product
/// that appears in a sale (archive it instead).
class RecordInUseException extends DataException {
  const RecordInUseException(super.message);
}
