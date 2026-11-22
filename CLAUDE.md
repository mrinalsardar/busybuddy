# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

BusyBuddy: local-first retail POS and inventory app.

## Commands

```
flutter test                    # all tests (DB tests use sqflite_common_ffi, no device needed)
flutter test test/data_integrity_test.dart --plain-name "<test name>"   # single test
flutter analyze                 # must stay "No issues found"; run before finishing a change
dart run build_runner build --delete-conflicting-outputs        # only if code-gen annotations are used
```

`riverpod_generator`, `json_serializable`, `build_runner` are in dev_dependencies but current code does not use them: providers and models are hand-written.

## Conventions

- Don't run `dart format` on whole files or dirs; most of the repo is unformatted and it would bury the real diff. Format only lines you touch.
- Remote is Bitbucket (no `gh`). Branches `feat/...`, `chore/...`, `fix/...`; PRs are opened in the Bitbucket web UI.

## Emulator verification

Tests and `flutter analyze` are not enough when a change touches UI (screens, widgets, dialogs, navigation, theme) or alters a user-visible flow (e.g. checkout, stock, settings). Also run it on the Android emulator before calling the change done. Pure DAO/model/util changes fully covered by tests can skip this; say that you skipped it.

- AVD: `Medium_Phone_API_37.0`. Start: `flutter emulators --launch Medium_Phone_API_37.0`, then `flutter run -d emulator-5554` (check id with `flutter devices`).
- `adb` is not on PATH: use `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`. The `android-cli` skill also covers screenshots and UI inspection.
- Drive the changed flow (`adb shell input tap/text`, `adb shell uiautomator dump` for coordinates), take a screenshot (`adb exec-out screencap -p > <scratchpad>/shot.png`) and look at it. Check the edge cases the change touches, not just the happy path.
- Report what was exercised and what was seen. If the emulator can't be run, say so; never claim UI verified without a screenshot or observed output.

## Architecture

**Data layer** (`core/db`, `core/dao`, `core/models`):
- `DatabaseHelper` is a singleton owning the one SQLite connection. Whole schema is created in `_onCreate` (version 1); `_onUpgrade` is an empty stub, so schema changes need a version bump plus migration there. `PRAGMA foreign_keys = ON` set in `onConfigure`; schema relies on `ON DELETE CASCADE`/`SET NULL`.
- `BaseDao<T>` gives generic CRUD (`insert` fails on an existing id; never use `ConflictAlgorithm.replace`, since SQLite's REPLACE deletes the row first and fires FK cascades). Each DAO subclass supplies `tableName`, `toMap`, `fromMap`, plus table-specific queries. DAOs fetch the DB from `DatabaseHelper()` themselves, not via injection.
- Money is integer minor units: columns end in `_minor`, fields in `Minor`. Never use `double` for amounts. Decimals per shop are `business_profile.currency_decimals` (0-3, ISO 4217 default). Parse, format and display only via `profile.money` (`MoneyFormat`, `core/utils/money.dart`). Currency and decimals are locked once the profile has products or sales (`ActiveProfileNotifier.updateProfile` throws), since changing decimals would rescale every stored amount.
- Customer totals are calculated from sales (`CustomerDao.getTotalSpentMinor`), not stored.
- `product.price_minor` is only a suggested price. The cart line's `unitPriceMinor` starts at it and can be edited at the POS (`CartNotifier.updatePrice`); `sale_item.unit_price_minor` records the actual price. Average selling price is calculated from sale items (`SaleItemDao.getAvgSellingPricesMinor`, `avgSellingPriceProvider`), not stored.
- Timestamps are UTC ISO-8601 text via `core/db/db_time.dart` (`toDbTime`/`fromDbTime`; SQL defaults use `sqlNow`). Calendar dates (expiry, expense) are `YYYY-MM-DD` (`toDbDate`). Query a day as a UTC range, not `date(created_at)`.
- Multi-table writes go through transactions, e.g. `SaleDao.recordSale` inserts sale + items and decrements stock atomically; `ProductDao.saveWithVariants` saves a product and its variant set.
- Stock: `business_profile.allow_oversell` (Settings) decides oversells. Off (default): `recordSale` throws `SaleRejectedException` and writes nothing if stock is short. On: stock goes negative (never clamped), so there is no `CHECK (stock_qty >= 0)`. A product with variants sold without a variant is always rejected. For a product with variants, `product.stock_qty` is the sum of its variants' stock: `saveWithVariants` sets it and `recordSale` decrements both.
- After any product/variant/sale write, call `invalidateProductViews(ref.invalidate)` (`inventory_providers.dart`). POS uses `posProductListProvider`, which ignores the Inventory search and filter.
- Products are archived (`archived = 1`), not deleted: `sale_item.product_id` has no ON DELETE action, so deleting a sold product fails. `sale_item.product_name` snapshots the name at sale time.
- Tables are scoped by `profile_id` (the `business_profile` row), except `backup_log`. SKU and barcode are unique per profile among non-archived products (partial unique indexes), so saves can fail with a unique-constraint error.

**State** (`core/providers/core_providers.dart`): one `Provider` per DAO, plus `activeProfileProvider` (`StateNotifier<AsyncValue<BusinessProfile?>>`) loaded from DB at startup. Null profile means onboarding. Feature providers read the profile from it and are `FutureProvider`s that must be `ref.invalidate`d after writes (see `checkoutProvider` in `sales_providers.dart`). Cart is a `ChangeNotifierProvider<CartNotifier>`, in-memory only. `routerProvider` builds the `GoRouter` once and re-runs `redirect` via `refreshListenable` on profile changes; don't make it `watch` the profile (a rebuilt router resets navigation).

**Business profile**: `type` is constrained in SQL to `shoes|fashion|grocery|general`; flags `variant_support` and `expiry_tracking` drive whether variants/expiry UI applies. Tax is not implemented yet (`taxAmount: 0`, "Phase 2"). `google_account_id` / `backup_log` are schema for a planned Drive backup, not implemented.
