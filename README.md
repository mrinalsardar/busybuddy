# BusyBuddy

BusyBuddy is a local-first retail point-of-sale (POS) and inventory app for small shops, built with Flutter. A shop owner and their staff can ring up sales, track stock and see sales history on a phone. The app works fully offline. When a backend is configured, it signs users in and syncs each shop's data between devices.

## Features

The app modules live under `lib/features/`:

- **Onboarding and shop profile** (`profile`): create a shop, choose its type (`shoes`, `fashion`, `grocery` or `general`), or join an existing shop with an invite code.
- **Sign-in** (`auth`): sign in with an emailed one-time code. Only available when a backend is configured (see [Backend](#backend)).
- **Inventory** (`inventory`): add, edit, search and filter products, with optional variants and expiry dates depending on the shop type. Products are archived, not deleted, once they have been sold. Stock changes are recorded as stock movements.
- **Point of sale** (`sales`): build a cart, edit the price of a line and charge the sale. Selling beyond stock is rejected unless the shop allows it.
- **Sales history** (`sales`): list of recorded sales.
- **Settings** (`settings`): allow selling beyond stock, currency and decimal places (locked once the shop has products or sales), staff invite codes (owner only) and sign-out.

Money is stored as integer minor units, so amounts never use floating point.

## Tech stack

- **Flutter / Dart** for the app. UI is built on `material_ui`, navigation uses `go_router`.
- **Riverpod** (`flutter_riverpod`) for state. Providers are written by hand.
- **PowerSync** (`powersync`) keeps a local SQLite database on each device. The app reads and writes this database, so it needs no network.
- **Supabase** provides Postgres, Auth and server functions. PowerSync syncs the local database with the Supabase Postgres database, using the sync rules in `powersync/sync-rules.yaml`. Local writes are queued and uploaded to Supabase by `SupabaseConnector` (`lib/core/db/supabase_connector.dart`).

## Prerequisites

- **Flutter** with Dart `^3.11.5` (the `environment.sdk` constraint in `pubspec.yaml`). The tests were run with Flutter 3.50.1 (Dart 3.14.0) on the stable channel. Flutter must be on your `PATH`.
- **JDK 17.** The Android build targets Java 17 (`android/app/build.gradle.kts`).
- **Android SDK** with an emulator image and `adb`. The Android build uses Gradle 9.6.0 (downloaded by the Gradle wrapper), Android Gradle Plugin 9.5.2 and Kotlin 2.4.21. Run `flutter doctor` to check your toolchain.
- **For the local backend only:** the [Supabase CLI](https://supabase.com/docs/guides/local-development) and Docker.

You do not need a Supabase or PowerSync account to run the app. The maintainer has no hosted accounts yet.

## Setup

```
git clone <repository-url>
cd busybuddy
flutter pub get
```

Code generation with `build_runner` is not needed. `riverpod_generator`, `json_serializable` and `build_runner` are listed in `dev_dependencies`, but the code uses no generated files: providers and models are hand-written.

### Backend configuration

The app reads three values at build time, passed with `--dart-define`:

| Name | Meaning |
|---|---|
| `SUPABASE_URL` | URL of the Supabase project |
| `SUPABASE_ANON_KEY` | Supabase anon (publishable) key |
| `POWERSYNC_URL` | URL of the PowerSync instance |

If any of the three is missing, the app starts without a backend. There is then no sign-in and no sync, and the app only shows and stores data on the device. Sign-in and sync need a Supabase project and a PowerSync instance that are set up as described in [`supabase/README.md`](supabase/README.md). Do not commit real values.

## Running

Start an Android emulator, then run the app:

```
flutter emulators                         # list the available emulators
flutter emulators --launch <emulator-id>
flutter devices                           # find the device id, e.g. emulator-5554
flutter run -d <device-id>
```

This runs the app on the local database only. To run it against a backend, add the values:

```
flutter run -d <device-id> \
  --dart-define=SUPABASE_URL=<url> \
  --dart-define=SUPABASE_ANON_KEY=<key> \
  --dart-define=POWERSYNC_URL=<url>
```

Android is the supported development platform. The repository also contains `ios/`, `linux/`, `macos/`, `web/` and `windows/` project folders from the Flutter template, which have not been verified.

When the app runs on an Android emulator, `127.0.0.1` is the emulator itself. Reach a service on your computer, such as the local Supabase stack, at `10.0.2.2` instead.

### Tests and analysis

```
flutter test                  # all tests; no device or server needed
flutter test test/data_integrity_test.dart --plain-name "<test name>"   # one test
flutter analyze               # should report "No issues found"
```

The database tests open a PowerSync database on a temporary file.

## Backend

The server side lives in `supabase/` and `powersync/`. [`supabase/README.md`](supabase/README.md) describes the schema, access rules, server functions, the upload contract and the PowerSync setup. Read it before you set up a backend.

To run Supabase locally (needs the Supabase CLI and Docker), run these in the repository root:

```
supabase start        # local stack; applies migrations on first start
supabase db reset     # re-create the database from supabase/migrations/
supabase test db      # run the pgTAP tests in supabase/tests/
supabase stop
```

`supabase start` prints the local API URL and keys. The local stack sends sign-in emails to Inbucket at http://127.0.0.1:54324, where you can read the one-time codes.

PowerSync is not part of the local Supabase stack. The sync rules are in [`powersync/sync-rules.yaml`](powersync/sync-rules.yaml), with one bucket per shop. A PowerSync instance must be pointed at the Supabase database and given these rules. The steps are in the PowerSync section of `supabase/README.md`.

## Project layout

```
lib/
  main.dart        entry point; starts Supabase and sync only if configured
  core/            auth, database (schema, PowerSync, upload connector), DAOs,
                   models, providers, router, theme and utilities
  features/        screens and providers: auth, home, inventory, profile,
                   sales, settings
test/              unit and database tests
supabase/          migrations, pgTAP tests, email templates, config and server docs
powersync/         PowerSync sync rules
android/ ios/ linux/ macos/ web/ windows/   Flutter platform projects
```

## Contributing

Run `flutter analyze` and `flutter test` before you open a change. Branch names start with `feat/`, `chore/` or `fix/`. `CLAUDE.md` describes the architecture and conventions in more detail.

No license file is included in the repository yet.
