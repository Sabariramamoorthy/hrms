#!/bin/bash
set -euo pipefail

# Openship runs this as root so the sites volume can be chowned, then drops
# to the frappe user. Bench refuses to run as root.
if [ "$(id -u)" -eq 0 ]; then
  mkdir -p /home/frappe/frappe-bench
  chown frappe:frappe /home/frappe/frappe-bench
  export HOME=/home/frappe
  export USER=frappe
  export LOGNAME=frappe
  exec runuser -u frappe --preserve-environment -- bash "$0" "$@"
fi

export HOME=/home/frappe
export PYENV_ROOT="${PYENV_ROOT:-/home/frappe/.pyenv}"
export NVM_DIR=/home/frappe/.nvm
export PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:/home/frappe/.local/bin:${NVM_DIR}/current/bin:${PATH}"
export BENCH_DEVELOPER=1
# shellcheck disable=SC1091
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

BENCH_DIR=/home/frappe/frappe-bench
SITE_NAME="${SITE_NAME:-${FRAPPE_SITE:-hrms.localhost}}"
DB_HOST="${FRAPPE_DB_HOST:-db}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
APP_PORT="${PORT:-8000}"
DB_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root123}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin@123}"
READY_MARK="${BENCH_DIR}/sites/.hrms-ready"

wait_for_mariadb() {
  echo "Waiting for MariaDB at ${DB_HOST}:3306..."
  for _ in $(seq 1 90); do
    if mysqladmin ping -h "${DB_HOST}" -uroot -p"${DB_ROOT_PASSWORD}" --silent --connect-timeout=2; then
      echo "MariaDB is ready."
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for MariaDB." >&2
  exit 1
}

wait_for_redis() {
  echo "Waiting for Redis at ${REDIS_HOST}:${REDIS_PORT}..."
  for _ in $(seq 1 90); do
    if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" ping 2>/dev/null | grep -q PONG; then
      echo "Redis is ready."
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for Redis." >&2
  exit 1
}

ensure_bench() {
  if [ -x "${BENCH_DIR}/env/bin/python" ]; then
    echo "Frappe bench already initialized."
    return 0
  fi

  echo "Initializing Frappe bench from the develop branch. First boot takes a long time."
  rm -rf /tmp/frappe-bench-init
  bench init --skip-redis-config-generation --frappe-branch develop /tmp/frappe-bench-init
  mkdir -p "${BENCH_DIR}/sites"
  tar -C /tmp/frappe-bench-init --exclude=sites -cf - . | tar -C "${BENCH_DIR}" -xf -
  if [ ! -f "${BENCH_DIR}/sites/apps.txt" ]; then
    cp -a /tmp/frappe-bench-init/sites/. "${BENCH_DIR}/sites/"
  fi
  rm -rf /tmp/frappe-bench-init
}

configure_bench() {
  cd "${BENCH_DIR}"
  bench set-mariadb-host "${DB_HOST}"
  bench set-redis-cache-host "redis://${REDIS_HOST}:${REDIS_PORT}/0"
  bench set-redis-queue-host "redis://${REDIS_HOST}:${REDIS_PORT}/1"
  bench set-redis-socketio-host "redis://${REDIS_HOST}:${REDIS_PORT}/2"
}

ensure_app() {
  local name="$1"
  shift
  if [ -d "${BENCH_DIR}/apps/${name}" ]; then
    echo "App ${name} is already installed in the bench."
    return 0
  fi
  echo "Installing ${name}..."
  bench get-app "$@"
}

bind_web() {
  cd "${BENCH_DIR}"
  python3 - "${APP_PORT}" <<'PY'
import sys
from pathlib import Path

port = sys.argv[1]
path = Path("Procfile")
lines = []
if path.exists():
    for line in path.read_text().splitlines():
        if line.startswith("redis_") or line.startswith("watch:"):
            continue
        if line.startswith("web:"):
            line = f"web: bench serve --host 0.0.0.0 --port {port}"
        lines.append(line)
if not any(line.startswith("web:") for line in lines):
    lines.insert(0, f"web: bench serve --host 0.0.0.0 --port {port}")
path.write_text("\n".join(lines) + "\n")
PY
}

ensure_site() {
  cd "${BENCH_DIR}"
  if [ -f "${READY_MARK}" ]; then
    echo "Site ${SITE_NAME} is already set up."
    return 0
  fi

  local force_flag=()
  if [ -d "${BENCH_DIR}/sites/${SITE_NAME}" ]; then
    force_flag=(--force)
  fi

  echo "Creating site ${SITE_NAME} and installing ERPNext and HRMS..."
  bench new-site "${SITE_NAME}" \
    "${force_flag[@]}" \
    --db-host "${DB_HOST}" \
    --db-root-username root \
    --db-root-password "${DB_ROOT_PASSWORD}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --mariadb-user-host-login-scope="%" \
    --install-app erpnext \
    --install-app hrms \
    --set-default

  bench --site "${SITE_NAME}" set-config developer_mode 0
  bench --site "${SITE_NAME}" enable-scheduler
  bench --site "${SITE_NAME}" clear-cache
  touch "${READY_MARK}"
  echo "Site setup complete."
}

echo "Starting Frappe HRMS..."
wait_for_mariadb
wait_for_redis
ensure_bench
configure_bench
ensure_app erpnext --branch develop erpnext
ensure_app hrms --branch develop https://github.com/Sabariramamoorthy/hrms.git
ensure_site
bind_web

echo "Starting Frappe on 0.0.0.0:${APP_PORT}..."
cd "${BENCH_DIR}"
exec bench start
