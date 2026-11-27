# Hosted setup (qa and prd)

How to set up the hosted backends, deploy to them and build the app against them. Background and decisions are in [issue #33](https://github.com/mrinalsardar/busybuddy/issues/33).

## Environments

| Env | Backend | Build values | Android application ID | App name |
|---|---|---|---|---|
| `dev` | local Docker stack (`dev/up.sh`) | `env/dev.json` | `io.github.mrinalsardar.busybuddy.dev` | BusyBuddy Dev |
| `qa` | one free Supabase project and one free PowerSync instance | `env/qa.json` | `io.github.mrinalsardar.busybuddy.qa` | BusyBuddy QA |
| `prd` | one free Supabase project and one free PowerSync instance | `env/prd.json` | `io.github.mrinalsardar.busybuddy` | BusyBuddy |

There is no hosted `stage`. For `dev`, see [Run the backend locally](../README.md#run-the-backend-locally). The rest of this page applies to `qa` and `prd`. Do every step once for each, and never share a password, key or database role between them. Do not copy `prd` data to `qa`.

## Public values and secrets

Only these three values go into the app. They are visible to anyone who has the app; row-level security protects the data.

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` (the publishable or anon key)
- `POWERSYNC_URL`

Everything else is a secret. Never put a secret into the app, an `env/` file, the repository, a log or a build artifact. Store each one in a password manager (the free tier of Bitwarden is enough), with a separate entry per environment:

| Secret | Notes |
|---|---|
| Supabase secret (`service_role`) key | Bypasses row-level security. |
| Supabase database password | Chosen when you create the project. |
| `powersync_role` password | The role reads every row. |
| Supabase access token | For the Supabase CLI. |
| PowerSync personal access token | For the PowerSync CLI. |
| Google OAuth web client secret | Once Google sign-in is added. It goes into the Supabase dashboard only. |

Turn on two-factor authentication on the Supabase, PowerSync and GitHub accounts.

## 1. Create the Supabase project and the PowerSync instance

Pick one region near the shops and use it for both services. A PowerSync instance's region cannot be changed later.

1. In the Supabase dashboard, create the project `busybuddy-qa` or `busybuddy-prd`. Generate a strong database password and save it in the password manager.
2. In the PowerSync dashboard, create the instance with the same name in the same region. Do not connect it to the database yet: the database needs steps 4 and 5 first.

Generate new keys and passwords in the hosted services. **Never reuse anything from `dev/` or `powersync/config.local.yaml` in a hosted project:** not the JWT secret, the Auth signing key, the anon or service key, or any password. This repository is public, so all of them are public.

## 2. Create the GitHub Environments

The deploy workflow reads its settings from two GitHub Environments, `qa` and `prd`.

**Create both environments with their protection rules before you add any secret.** GitHub creates a missing environment automatically when a workflow job names it, with **no protection rules**. An environment you did not set up yourself may therefore exist and be unprotected: check its rules.

In the repository, open **Settings, Environments, New environment**:

| Setting | `qa` | `prd` |
|---|---|---|
| Deployment branches and tags | **Selected branches and tags**, with one branch rule: `main` | the same |
| Required reviewers | off | on, with the maintainer as reviewer |
| Prevent self-review | | **off**: there is a single maintainer, who must be able to approve their own run |
| Allow administrators to bypass configured protection rules | | off |

The branch rule is what keeps another branch from reading the secrets: a branch can change the workflow file, but not this rule. Required reviewers and these environment features are available on a free plan because the repository is public. A private repository needs a paid plan, and required reviewers need GitHub Enterprise ([GitHub docs](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)).

## 3. Add the environment secrets and variables

Add these to each of the two environments, with that environment's own values. Add them as **environment** secrets and variables only. Do not create repository or organization secrets or variables with these names: every job could read them.

| Name | Kind | Value |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | secret | A Supabase personal access token (Supabase dashboard, Account, Access Tokens). |
| `SUPABASE_DB_PASSWORD` | secret | The project's database password. |
| `PS_ADMIN_TOKEN` | secret | A [PowerSync personal access token](https://dashboard.powersync.com/account/access-tokens). |
| `SUPABASE_PROJECT_REF` | variable | The project id in the Supabase dashboard URL. |
| `POWERSYNC_INSTANCE_ID` | variable | The instance id in the PowerSync dashboard URL, or from `powersync fetch instances`. |
| `DEPLOY_ENVIRONMENT` | variable | The environment's own name: `qa` or `prd`. |

A deploy job stops before it contacts either service if one of these is missing, or if `DEPLOY_ENVIRONMENT` is not the job's environment. Before `prd`, the workflow also stops unless the `prd` environment has required reviewers and a deployment branch rule. It does not check which branch the rule allows, so keep it at `main`.

`powersync_role`'s password and the Supabase secret key are not GitHub secrets: the workflow does not use them.

Also turn on secret scanning and push protection (repository **Settings**). Workflow logs of a public repository are public. GitHub masks secret values in them, but not variables, so never store a secret as a variable.

## 4. Run the first deploy

The [**Deploy backend**](../.github/workflows/deploy.yml) workflow is the only way schema and sync rules reach `qa` and `prd`. Do not edit the schema or the sync rules in a dashboard.

To run it, open **Actions, Deploy backend, Run workflow** and choose `main`. It runs only when started by hand, never on a push or a pull request, so merging does not deploy anything. It runs these jobs in order:

1. **database tests**: `supabase test db`, as in CI.
2. **deploy qa**: `supabase db push` of `supabase/migrations`, then `powersync deploy sync-config` of [`powersync/sync-rules.yaml`](../powersync/sync-rules.yaml).
3. **check prd protection**.
4. **deploy prd**: waits for approval (**Review deployments**), then runs the same steps as `qa` against `prd`.

One run deploys at a time. A run that waits for approval holds back later runs, so approve or reject it. Before you approve, check that `qa` works with the deployed commit.

**Never re-run a run, or any of its jobs, once a newer run has started deploying.** A re-run deploys the old run's commit, and can replace newer sync rules in `qa` or `prd` with older ones. The workflow does not block this. Start a new run from `main` instead.

**On the first run, the sync rules step is expected to fail**, because PowerSync is not connected yet. The migrations are applied before it. Do steps 5 and 6 for `qa`, then run the workflow again. When it reaches `prd` for the first time, approve it, let the sync rules step fail in the same way, do steps 5 and 6 for `prd`, then re-run the failed job and approve it again.

## 5. Create the PowerSync database role

After the first migrations are applied, run these statements in the Supabase SQL editor, with a new, unique password for each environment. Save the password in the password manager.

```sql
create role powersync_role with replication bypassrls login password '<unique-password>';
grant select on all tables in schema public to powersync_role;
alter default privileges in schema public grant select on tables to powersync_role;
```

The last statement covers tables that later migrations add. It applies to tables created by the role that runs it (`postgres` in the SQL editor).

Do not create a publication, even where PowerSync's own instructions say to: the migrations already create the `powersync` publication with the synced tables. PowerSync Cloud keeps its own bucket storage, so do not create the `powersync_storage` database that the local stack uses.

## 6. Connect PowerSync

In the PowerSync dashboard, for the instance of the same environment:

1. **Database connection.** In Supabase, open **Connect** and copy the **Direct connection** string. Do not use a pooler connection: replication does not work through the transaction pooler. Paste it into the PowerSync **URI** field, then set the username to `powersync_role` and the password to the one from step 5. Keep the SSL mode at `verify-full`. Test the connection, then save it.
2. **Client auth.** Select **Use Supabase Auth**. With Supabase JWT signing keys, leave the JWT secret field empty. The instance must verify tokens against `<SUPABASE_URL>/auth/v1/.well-known/jwks.json` with the audience `authenticated`. If you configure auth by hand, enter these two values. Save and deploy.

Then run the workflow again (step 4). A warning that `bucket_definitions` is deprecated is expected.

## 7. Sign-in (current state)

The decision is Google sign-in only for `qa` and `prd`, but the app does not have it yet. Today the app signs in only with an emailed one-time code. Until Google sign-in lands:

- Keep the email provider enabled.
- Set the `magic_link` and `confirmation` email templates to show `{{ .Token }}`, as in `supabase/templates/` (dashboard: Authentication, Email Templates).
- The built-in Supabase email service delivers only to the addresses of the project's team members. Other users get no code unless you configure custom SMTP.

When Google sign-in lands, `qa` and `prd` need no email templates, and their email provider will be disabled. Emailed codes then remain for `dev` only.

## 8. Build each flavor

Create the file for each environment from the committed example, then fill in the three public values: the project URL and publishable (anon) key from the Supabase dashboard, and the instance URL from the PowerSync dashboard.

```
cp env/example.json env/qa.json
```

Git ignores every `env/*.json` file except `env/example.json`. For `dev`, generate the file instead: `dev/defines.sh emulator > env/dev.json`.

`--flavor` selects the application ID and app name. `--dart-define-from-file` selects the backend. The two are independent, so always pass the matching pair.

```
flutter run -d <device-id> --flavor dev --dart-define-from-file=env/dev.json
flutter build apk --release --flavor qa --dart-define-from-file=env/qa.json
flutter build appbundle --release --flavor prd --dart-define-from-file=env/prd.json
```

Without `--flavor`, Flutter builds `dev` (`default-flavor` in `pubspec.yaml`). If the file is not passed, or any of the three values is missing or empty, the app runs with no backend. A copy of the example that you did not fill in counts as configured, and sign-in fails.

Release builds are still signed with the debug keys (`android/app/build.gradle.kts`), so they are not ready for a store.

The application ID used to be `com.example.busybuddy` (with the `.dev` and `.qa` suffixes for those flavors). Android treats the new ID as a different app: on a device that has an old app, every flavor installs next to it as a separate app, and the old app's local data does not move to the new one. Do not uninstall an old app that holds data you have not synced: uninstalling deletes it. A new build installs over an app with the same application ID only if it is signed with the same key, and each computer has its own debug key. If Android refuses the update, the same warning about uninstalling applies.

### iOS

`ios/` has the schemes `dev`, `qa` and `prd`, each with `Debug-`, `Release-` and `Profile-` build configurations, the same bundle ID suffixes and app names as Android. **They have never been built:** they were written without a macOS host. On a Mac:

1. Open `ios/Runner.xcworkspace` in Xcode and check that the three schemes and their build configurations are there.
2. Set a signing team for each bundle ID.
3. Run `flutter build ios --flavor qa --no-codesign --dart-define-from-file=env/qa.json`, then check the app name and bundle ID.
4. If Flutter creates a `Podfile`, map all the build configurations to `:debug` or `:release` in its `project 'Runner'` block.

## Update the PowerSync CLI

The workflow installs the CLI with `npm ci` from [`package.json`](../.github/actions/deploy-backend/package.json) and its [lockfile](../.github/actions/deploy-backend/package-lock.json), so `qa` and `prd` get the same dependency versions from the same commit. To change the CLI version, or to pick up newer dependencies, update the files and commit them.

For a new CLI version, replace `<version>` with an exact version:

```
cd .github/actions/deploy-backend
npm install --package-lock-only --ignore-scripts --save-exact powersync@<version>
```

To pick up newer dependencies of the same CLI version:

```
cd .github/actions/deploy-backend
npm update --package-lock-only --ignore-scripts
```

Review the changes before you commit them: this code runs with `PS_ADMIN_TOKEN`.

## Free-tier limits

- **Pausing.** A free Supabase project pauses after about 7 days without API activity. A free PowerSync instance is deactivated after 1 week with no deploys and no client connections. Reactivate each one by hand in its dashboard. PowerSync then processes the database again from the start, so devices sync again. `qa` can pause between test rounds: resume both services before you test or deploy.
- **No backups.** Supabase Free has no backups and no point-in-time recovery. This project has no scheduled backup yet.
- **50 clients.** PowerSync Free allows 50 peak concurrent clients per organization, so `qa` and `prd` share the limit.
- **Other limits.** Supabase Free allows 2 active projects. PowerSync Free allows 2 instances with 1 source database each, 2 GB synced per month and 500 MB hosted.

These limits are the ones recorded in [issue #33](https://github.com/mrinalsardar/busybuddy/issues/33). Check the current pricing pages before you rely on them. Move `prd` to paid plans once real shops depend on it.
