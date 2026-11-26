# BusyBuddy

BusyBuddy is a local-first retail point-of-sale (POS) and inventory app for small shops, built with Flutter. A shop owner and their staff can ring up sales, track stock and see sales history on a phone. The app works fully offline. When a backend is configured, it signs users in and syncs each shop's data between devices.

## Features

The app modules live under `lib/features/`:

- **Onboarding and shop profile** (`profile`): create a shop, choose its type (`shoes`, `fashion`, `grocery` or `general`), or join an existing shop with an invite code.
- **Sign-in** (`auth`): sign in with an emailed one-time code. Only available when a backend is configured (see [Backend](#backend)).
- **Inventory** (`inventory`): add, edit, search and filter products, with optional variants and expiry dates depending on the shop type. Products are archived, not deleted, once they have been sold. Stock changes are recorded as stock movements.
- **Point of sale** (`sales`): build a cart, edit the price of a line and charge the sale. Selling beyond stock is rejected unless the shop allows it.
- **Sales history** (`sales`): list of recorded sales; tap a sale to see its line items, payment and totals.
- **Settings** (`settings`): choose a Light, Dark or System theme (System, the default, follows the device setting; the choice is saved on the device, is not synced, and staff can change it too), allow selling beyond stock, currency and decimal places (locked once the shop has products or sales), staff invite codes (owner only) and sign-out.

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
- **For the local backend and the containerised tests:** Docker with Compose v2 (`docker compose`). No other install is needed for those; see [Run the backend locally](#run-the-backend-locally). The [Supabase CLI](https://supabase.com/docs/guides/local-development) is only needed for `supabase test db` and the [CLI alternative](#alternative-the-supabase-cli).

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

If any of the three is missing, the app starts without a backend. There is then no sign-in and no sync, and the app only shows and stores data on the device. Sign-in and sync need a Supabase project and a PowerSync instance. To run both on your computer, follow [Run the backend locally](#run-the-backend-locally). For a hosted project, see [`supabase/README.md`](supabase/README.md). Do not commit real values.

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

Android is the supported development platform. The repository also contains an `ios/` project folder from the Flutter template, which has not been verified.

When the app runs on an Android emulator, `127.0.0.1` is the emulator itself. Reach a service on your computer, such as the local Supabase stack, at `10.0.2.2` instead (see [Run the backend locally](#run-the-backend-locally)).

### Tests and analysis

```
flutter test                  # all tests; no device or server needed
flutter test test/data_integrity_test.dart --plain-name "<test name>"   # one test
flutter analyze               # should report "No issues found"
```

The database tests open a PowerSync database on a temporary file.

## Backend

The server side lives in `supabase/` and `powersync/`. [`supabase/README.md`](supabase/README.md) describes the schema, access rules, server functions, the upload contract and the PowerSync setup. Read it before you set up a backend.

### Run the backend locally

`dev/` defines a local test environment as Docker Compose services. It runs the services sign-in and sync need and nothing else: Postgres with the repository's migrations applied, Supabase Auth, the REST API, an API gateway, the Mailpit mail inbox and PowerSync. Only Docker is needed. Run the commands from the repository root.

| Command | What it does |
|---|---|
| `dev/up.sh` | Starts the stack, waits until it is healthy and creates the seed accounts. Safe to run again. |
| `dev/defines.sh emulator` | Prints the `--dart-define` flags for an Android emulator (`desktop` for an app that runs on your computer). |
| `dev/code.sh <email>` | Prints the newest sign-in code mailed to that address. |
| `dev/test.sh` | Runs `flutter pub get`, `flutter analyze` and `flutter test` in the pinned toolchain image. |
| `dev/down.sh` | Stops the stack and keeps its data. `dev/down.sh --reset` also deletes the data. |

**Start the backend and run the app.**

```
dev/up.sh
flutter emulators --launch <emulator-id>
flutter run -d <device-id> $(dev/defines.sh emulator)
```

The first `dev/up.sh` pulls the images, which takes a few minutes. It starts the services in this order: Postgres, Auth, Storage, a one-shot `setup` job, then PowerSync. `setup` applies `supabase/migrations/` once Auth has created its schema, creates the `powersync_role` database role and the `powersync_storage` database, and exits. PowerSync reads the committed [`powersync/config.local.yaml`](powersync/config.local.yaml) and [`powersync/sync-rules.yaml`](powersync/sync-rules.yaml) unchanged: the Compose services use the container names that config expects. All ports are published on `127.0.0.1` only:

| Service | Address |
|---|---|
| API gateway (`/auth/v1`, `/rest/v1`, `/storage/v1`) | http://127.0.0.1:54321 |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Mailpit inbox | http://127.0.0.1:54324 |
| PowerSync | http://127.0.0.1:8080 |

These are the ports of `supabase start`, so run only one of the two stacks at a time. An Android emulator reaches your computer at `10.0.2.2`, which `dev/defines.sh emulator` uses. A physical device cannot reach `127.0.0.1` on your computer: publish the ports on your LAN address in `dev/compose.yaml` and replace the host in the `dev/defines.sh` output.

**Accounts and sign-in codes.** `dev/up.sh` creates three confirmed accounts: `owner@busybuddy.test`, `staff@busybuddy.test` and `other@busybuddy.test`. They have no password and no shop. Sign in with an emailed code: enter the address in the app, then run `dev/code.sh owner@busybuddy.test` and type the 6-digit code it prints. Any other address also works, because sign-up is on. The Mailpit inbox at http://127.0.0.1:54324 shows every mail.

**Run the tests.**

```
dev/test.sh
dev/test.sh flutter test test/data_integrity_test.dart --plain-name "<test name>"
```

The first run builds the `busybuddy-dev-test` image (JDK 17, Flutter 3.47.9, Android SDK platform 36 and build-tools 36.0.0). It is several GB and takes a few minutes. The repository is mounted into the container, so results match your working tree, and the container runs as your user id. The Flutter version is the one `.github/workflows/ci.yml` uses: change both together. The tests need no backend.

**Stop and reset.**

```
dev/down.sh            # stop; the database, PowerSync storage and mail are kept
dev/down.sh --reset    # stop and delete them; the next dev/up.sh starts from scratch
```

Both commands act only on the Compose project `busybuddy-dev`. To rebuild the test image after you change `dev/test-runner/Dockerfile`, run `docker compose -f dev/compose.yaml build test`. The test container's pub cache is the separate volume `busybuddy-dev_pub-cache`, which a reset keeps. After you change a migration, run `dev/down.sh --reset` and `dev/up.sh`: `setup` applies a migration file once and does not re-apply an edited one.

**Platform notes.**

- *Linux:* Docker Engine with the Compose plugin.
- *macOS:* Docker Desktop.
- *Windows:* use WSL 2 for everything. Clone the repository inside the WSL distro (not under `/mnt/c`) and run the scripts from a WSL shell. Docker must be reachable from WSL: enable Docker Desktop's WSL integration (Settings, Resources, WSL integration, your distro), or install Docker Engine inside the distro. No Windows-side CLI or copied project folder is needed. An Android emulator on the Windows side reaches the stack at `10.0.2.2`, because WSL 2 forwards the ports published on `127.0.0.1`.

**Testing a forced sign-out.** The access token lives `GOTRUE_JWT_EXP` seconds (3600), so a revoked session shows up in the app only after up to an hour. For a test, set `GOTRUE_JWT_EXP: "60"` in `dev/compose.yaml` (do not commit it) and run `dev/up.sh`. Then `docker compose -f dev/compose.yaml exec db psql -U postgres -c "delete from auth.sessions"` signs the app out within about a minute.

**What is where.** `dev/compose.yaml` pins every image version. The Auth signing key, JWT secret, anon key and service key in `dev/compose.yaml` and `dev/lib.sh` are throwaway local values: never use them for a hosted project. The sign-in email templates are `supabase/templates/`, served to Auth by the gateway (`dev/gateway.conf`). The server side is described in [`supabase/README.md`](supabase/README.md).

### Alternative: the Supabase CLI

`supabase start` runs the same services and also gives you `supabase test db` (the pgTAP tests). It needs the Supabase CLI and a Docker socket. The steps below start Supabase, create the PowerSync role and storage database by hand and run PowerSync with `docker run`. Run every command from the repository root, except where a step says otherwise.

**1. Start Supabase.** Sign-in and sync need only the database, Auth, the API gateway (`kong`), `rest`, `storage-api` (product pictures) and the mail container. Exclude the rest, so the stack needs less RAM and starts faster:

```
supabase start -x realtime,imgproxy,edge-runtime,logflare,vector,supavisor,studio,postgres-meta
```

The first start pulls every image, including the excluded ones, which takes a few minutes. It applies `supabase/migrations/` and prints the API URL (`http://127.0.0.1:54321`), the **Publishable** key (`sb_publishable_...`) and the database URL (`postgresql://postgres:postgres@127.0.0.1:54322/postgres`). `supabase status` prints them again.

`supabase start` with no `-x` also works, but starts ten or more services and needs several GB of RAM.

*Windows with WSL:* the Supabase CLI needs a Docker socket. Without Docker Desktop's WSL integration (Settings, Resources, WSL integration, enable your distro), there is none in WSL, and a project path inside the WSL distro fails at container creation with `accessing specified distro mount service: stat /run/guest-services/distro-services/...sock: no such file or directory`. Either enable the integration, or run the CLI on the Windows side from a copy of the project on a Windows path, for example in PowerShell:

```
$dst = "$env:TEMP\busybuddy-backend"
New-Item -ItemType Directory $dst
Copy-Item -Recurse <path-to-repo>\supabase, <path-to-repo>\powersync $dst
cd $dst
npx supabase start -x realtime,imgproxy,edge-runtime,logflare,vector,supavisor,studio,postgres-meta
```

Use `npx supabase ...` in place of `supabase ...` in the steps below, and `docker` from that same Windows shell.

**2. Create the PowerSync database role and storage database.** PowerSync reads the Supabase database with its own role and keeps its bucket storage in a second database, so no MongoDB is needed. Run these as three separate commands. `psql -c` with several statements runs them as one transaction, and `create database` cannot run inside one, so a combined call rolls the role back and PowerSync later fails with `password authentication failed for user "powersync_role"`.

```
docker exec supabase_db_busybuddy psql -U postgres -c "create role powersync_role with replication bypassrls login password 'psync'"
docker exec supabase_db_busybuddy psql -U postgres -c "grant select on all tables in schema public to powersync_role"
docker exec supabase_db_busybuddy psql -U postgres -c "create database powersync_storage"
```

The password `psync` is the one in `powersync/config.local.yaml`. It is for local use only.

**3. Start the PowerSync service.** [`powersync/config.local.yaml`](powersync/config.local.yaml) points the service at the local database (`supabase_db_busybuddy`), keeps bucket storage in `powersync_storage`, and checks sign-in tokens against the local Auth JWKS endpoint (`http://supabase_kong_busybuddy:8000/auth/v1/.well-known/jwks.json`, audience `authenticated`). The container must join the Supabase Docker network, so these hostnames resolve:

```
docker run -d --name bb_powersync --network supabase_network_busybuddy -p 8080:8080 \
  -v "$PWD/powersync:/config" \
  -e POWERSYNC_CONFIG_PATH=/config/config.local.yaml \
  journeyapps/powersync-service:latest
```

On Windows, replace `$PWD/powersync` with the Windows path of the `powersync` folder, for example `"$env:TEMP\busybuddy-backend\powersync"` in PowerShell.

Check `docker logs bb_powersync`. It should show `Replicating "public"."<table>"` for each publication table and then `Activated new replication stream`. A warning about `bucket_definitions` being deprecated is expected. If the image pull fails with `unexpected EOF`, run `docker pull journeyapps/powersync-service:latest` again.

**4. Run the app against the stack.** Pass the three values with `--dart-define`. `SUPABASE_ANON_KEY` takes the **Publishable** key from step 1. An Android emulator cannot reach your computer at `127.0.0.1`, so use `10.0.2.2` there. A physical device needs your computer's LAN address instead.

```
flutter run -d <device-id> \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key> \
  --dart-define=POWERSYNC_URL=http://10.0.2.2:8080
```

On a target that runs on your computer, use `http://127.0.0.1:54321` and `http://127.0.0.1:8080`.

**5. Read the sign-in code.** The local stack sends emails to Mailpit (the container is still named `supabase_inbucket_busybuddy`). Open http://127.0.0.1:54324 and read the 6-digit code, or use its API:

```
curl "http://127.0.0.1:54324/api/v1/search?query=to:<email>"      # find the message ID
curl "http://127.0.0.1:54324/api/v1/message/<ID>"                  # the code is in the Text field
```

**Stop and reset.**

```
docker rm -f bb_powersync
supabase stop                 # add --no-backup to also delete the local data
supabase db reset             # re-create the database from supabase/migrations/
supabase test db              # run the pgTAP tests in supabase/tests/
```

After `supabase db reset` or `supabase stop --no-backup`, repeat steps 2 and 3 (the role and `powersync_storage` are gone). Run `docker rm -f bb_powersync` first.

**Testing a forced sign-out.** `jwt_expiry` in `supabase/config.toml` is 3600 seconds, so a revoked session shows up in the app only after up to an hour. For a test, change it to `jwt_expiry = 60` before step 1 and do not commit that change. Then `delete from auth.sessions` (through `docker exec supabase_db_busybuddy psql -U postgres -c "delete from auth.sessions"`) signs the app out within about a minute.

The server side is described in [`supabase/README.md`](supabase/README.md): schema, access rules, server functions, the upload contract and the sync rules. The sync rules are in [`powersync/sync-rules.yaml`](powersync/sync-rules.yaml), with one bucket per shop. The CLI prints that all local services bind to `0.0.0.0` and use shared default keys and passwords, so run this stack only on a network you trust. For a hosted PowerSync instance, create your own config: `config.local.yaml` is for the local stack only.

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
powersync/         PowerSync sync rules and the local service config
android/ ios/      Flutter platform projects
```

## Contributing

Run `flutter analyze` and `flutter test` before you open a change. Branch names start with `feat/`, `chore/` or `fix/`. `CLAUDE.md` describes the architecture and conventions in more detail.

No license file is included in the repository yet.
