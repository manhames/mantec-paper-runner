#!/usr/bin/env bash
set -euo pipefail

# One-shot bootstrap for a fresh Ubuntu DigitalOcean droplet.
# Installs Docker, clones MANTEC, configures paper env, smoke-tests, then starts 14-day paper run.

if [[ "${EUID}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

set_env_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped
  escaped="$(printf '%s' "$value" | sed -e 's/[\/&]/\\&/g')"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s/^${key}=.*/${key}=${escaped}/" "$file"
  else
    echo "${key}=${value}" >>"$file"
  fi
}

MANTEC_REPO_URL="${MANTEC_REPO_URL:-https://github.com/manhames/mantec-paper-core.git}"
MANTEC_DIR="${MANTEC_DIR:-/opt/mantec}"
ENV_FILE="${MANTEC_DIR}/analysis/real_world_testsing/.env"
DATA_ENV_FILE="${MANTEC_DIR}/data/.env"
FORWARD_START_UTC="${FORWARD_START_UTC:-$(date -u +%Y-%m-%dT00:00:00Z)}"
PAPER_RUNTIME_HOURS="${PAPER_RUNTIME_HOURS:-336}"
TOTAL_NET_WORTH_USD="${TOTAL_NET_WORTH_USD:-100000}"
TEST_ALLOC_FRACTION="${TEST_ALLOC_FRACTION:-0.01}"
COINGECKO_API_KEY="${COINGECKO_API_KEY:-}"
DATABASE_URL="${DATABASE_URL:-postgresql://mantec:mantec@timescaledb:5432/mantec}"
CHAINS="${CHAINS:-binance-smart-chain}"
BACKFILL_START_DATE="${BACKFILL_START_DATE:-2025-01-01}"
BOOTSTRAP_DATA="${BOOTSTRAP_DATA:-true}"
BOOTSTRAP_TOP="${BOOTSTRAP_TOP:-1200}"
BOOTSTRAP_LIMIT="${BOOTSTRAP_LIMIT:-400}"
BOOTSTRAP_CONCURRENCY="${BOOTSTRAP_CONCURRENCY:-8}"
GITHUB_USER="${GITHUB_USER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

AUTH_MANTEC_REPO_URL="${MANTEC_REPO_URL}"
if [[ -n "${GITHUB_USER}" && -n "${GITHUB_TOKEN}" && "${MANTEC_REPO_URL}" == https://github.com/* ]]; then
  AUTH_MANTEC_REPO_URL="$(echo "${MANTEC_REPO_URL}" | sed -E "s#^https://github.com/#https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/#")"
fi

echo "==> Installing base packages"
apt-get update
apt-get install -y ca-certificates curl gnupg git lsb-release

echo "==> Installing Docker Engine + Compose plugin"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  >/etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker

echo "==> Cloning/updating MANTEC repo at ${MANTEC_DIR}"
if [[ -d "${MANTEC_DIR}/.git" ]]; then
  git -C "${MANTEC_DIR}" remote set-url origin "${AUTH_MANTEC_REPO_URL}" || true
  git -C "${MANTEC_DIR}" fetch --all
  git -C "${MANTEC_DIR}" pull --ff-only
  git -C "${MANTEC_DIR}" remote set-url origin "${MANTEC_REPO_URL}" || true
else
  git clone "${AUTH_MANTEC_REPO_URL}" "${MANTEC_DIR}"
  git -C "${MANTEC_DIR}" remote set-url origin "${MANTEC_REPO_URL}" || true
fi

echo "==> Preparing env file"
cp -n "${MANTEC_DIR}/analysis/real_world_testsing/.env.example" "${ENV_FILE}"
cp -n "${MANTEC_DIR}/data/.env.example" "${DATA_ENV_FILE}"
set_env_key "${ENV_FILE}" "DATABASE_URL" "${DATABASE_URL}"
set_env_key "${ENV_FILE}" "FORWARD_START_UTC" "${FORWARD_START_UTC}"
set_env_key "${ENV_FILE}" "PAPER_RUNTIME_HOURS" "${PAPER_RUNTIME_HOURS}"
set_env_key "${ENV_FILE}" "TOTAL_NET_WORTH_USD" "${TOTAL_NET_WORTH_USD}"
set_env_key "${ENV_FILE}" "TEST_ALLOC_FRACTION" "${TEST_ALLOC_FRACTION}"
set_env_key "${ENV_FILE}" "LIVE_EXECUTION" "false"
set_env_key "${ENV_FILE}" "DEX_EXECUTION_MODE" "simulated"
if [[ -n "${COINGECKO_API_KEY}" ]]; then
  set_env_key "${ENV_FILE}" "COINGECKO_API_KEY" "${COINGECKO_API_KEY}"
  set_env_key "${DATA_ENV_FILE}" "COINGECKO_API_KEY" "${COINGECKO_API_KEY}"
fi
set_env_key "${DATA_ENV_FILE}" "DATABASE_URL" "${DATABASE_URL}"

cd "${MANTEC_DIR}"
echo "==> Starting DB service"
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml up -d timescaledb

echo "==> Initializing DB schema"
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml run --rm paper_bot \
  python data/scripts/init_db.py

if [[ "${BOOTSTRAP_DATA}" == "true" || "${BOOTSTRAP_DATA}" == "1" ]]; then
  echo "==> Seeding token universe"
  docker compose -f analysis/real_world_testsing/docker-compose.paper.yml run --rm paper_bot \
    python data/scripts/seed_universe.py --top "${BOOTSTRAP_TOP}" --chains "${CHAINS}"

  echo "==> Backfilling hourly data (limit=${BOOTSTRAP_LIMIT})"
  docker compose -f analysis/real_world_testsing/docker-compose.paper.yml run --rm paper_bot \
    python data/scripts/backfill_hourly.py --start-date "${BACKFILL_START_DATE}" --limit "${BOOTSTRAP_LIMIT}" --chains "${CHAINS}" --concurrency "${BOOTSTRAP_CONCURRENCY}"

  echo "==> Backfilling universe snapshots from DB"
  docker compose -f analysis/real_world_testsing/docker-compose.paper.yml run --rm paper_bot \
    python data/scripts/backfill_universe_snapshots_from_db.py --start-date "${BACKFILL_START_DATE}" --end-date "$(date -u +%Y-%m-%d)" --chains "${CHAINS}" --step-days 7 --top-n 10000
else
  echo "==> Skipping data bootstrap (BOOTSTRAP_DATA=${BOOTSTRAP_DATA})"
fi

echo "==> Running container smoke test (unit tests)"
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml run --rm paper_bot \
  python -m unittest analysis.real_world_testsing.tests.test_dex_executor -v

echo "==> Running one paper cycle"
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml run --rm paper_bot \
  python analysis/real_world_testsing/live_test_runner.py --once --skip-update

echo "==> Starting 14-day paper bot"
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml up -d --build
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml ps

echo
echo "Bootstrap complete."
echo "Follow logs with:"
echo "  cd ${MANTEC_DIR}"
echo "  docker compose -f analysis/real_world_testsing/docker-compose.paper.yml logs -f paper_bot"
