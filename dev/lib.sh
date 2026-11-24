# Shared by the scripts in this folder. Source it; do not run it.
# Values are for the local stack only (see compose.yaml). The anon and service
# keys are HS256 tokens signed with the JWT secret in compose.yaml.

BB_DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_API_URL="${BB_API_URL:-http://127.0.0.1:54321}"
BB_MAIL_URL="${BB_MAIL_URL:-http://127.0.0.1:54324}"
BB_POWERSYNC_URL="${BB_POWERSYNC_URL:-http://127.0.0.1:8080}"
BB_ANON_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJidXN5YnVkZHktbG9jYWwiLCJyb2xlIjoiYW5vbiIsImV4cCI6MjA4Mjc1ODQwMH0.FSus65ABjMXc0MHl-nP0S5xCkHEw7_X6akaFc8nCJ3U'
BB_SERVICE_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJidXN5YnVkZHktbG9jYWwiLCJyb2xlIjoic2VydmljZV9yb2xlIiwiZXhwIjoyMDgyNzU4NDAwfQ.bAUS_oijZLEg1xBU-A3AKeHFa4JPkMIu8ouah_f99Mk'

# Throwaway accounts that seed.sh creates.
BB_SEED_EMAILS=(owner@busybuddy.test staff@busybuddy.test other@busybuddy.test)

# Compose needs the user's id so files the test container writes into the
# repository (.dart_tool, build/) belong to the user, not root.
bb_compose() {
  HOST_UID="${HOST_UID:-$(id -u)}" HOST_GID="${HOST_GID:-$(id -g)}" \
    docker compose -f "$BB_DEV_DIR/compose.yaml" "$@"
}
