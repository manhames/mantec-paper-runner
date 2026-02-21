#!/usr/bin/env bash
set -euo pipefail

# One-shot bootstrap for a fresh Ubuntu DigitalOcean droplet.
# Installs Docker, clones MANTEC, configures paper env, smoke-tests, then starts 14-day paper run.

if [[ "${EUID}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

require_var() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required env var: ${key}"
    exit 1
  fi
}

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

require_var MANTEC_REPO_URL

MANTEC_DIR="${MANTEC_DIR:-/opt/mantec}"
ENV_FILE="${MANTEC_DIR}/analysis/real_world_testsing/.env"
FORWARD_START_UTC="${FORWARD_START_UTC:-$(date -u +%Y-%m-%dT00:00:00Z)}"
PAPER_RUNTIME_HOURS="${PAPER_RUNTIME_HOURS:-336}"
TOTAL_NET_WORTH_USD="${TOTAL_NET_WORTH_USD:-100000}"
TEST_ALLOC_FRACTION="${TEST_ALLOC_FRACTION:-0.01}"
COINGECKO_API_KEY="${COINGECKO_API_KEY:-}"
DATABASE_URL="${DATABASE_URL:-postgresql://mantec:mantec@timescaledb:5432/mantec}"

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
  git -C "${MANTEC_DIR}" fetch --all
  git -C "${MANTEC_DIR}" pull --ff-only
else
  git clone "${MANTEC_REPO_URL}" "${MANTEC_DIR}"
fi

echo "==> Preparing env file"
cp -n "${MANTEC_DIR}/analysis/real_world_testsing/.env.example" "${ENV_FILE}"
set_env_key "${ENV_FILE}" "DATABASE_URL" "${DATABASE_URL}"
set_env_key "${ENV_FILE}" "FORWARD_START_UTC" "${FORWARD_START_UTC}"
set_env_key "${ENV_FILE}" "PAPER_RUNTIME_HOURS" "${PAPER_RUNTIME_HOURS}"
set_env_key "${ENV_FILE}" "TOTAL_NET_WORTH_USD" "${TOTAL_NET_WORTH_USD}"
set_env_key "${ENV_FILE}" "TEST_ALLOC_FRACTION" "${TEST_ALLOC_FRACTION}"
set_env_key "${ENV_FILE}" "LIVE_EXECUTION" "false"
set_env_key "${ENV_FILE}" "DEX_EXECUTION_MODE" "simulated"
if [[ -n "${COINGECKO_API_KEY}" ]]; then
  set_env_key "${ENV_FILE}" "COINGECKO_API_KEY" "${COINGECKO_API_KEY}"
fi

echo "==> Running container smoke test (single cycle, no update/feature refresh)"
cd "${MANTEC_DIR}"
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml run --rm paper_bot \
  python analysis/real_world_testsing/live_test_runner.py --once --skip-update --skip-feature-refresh

echo "==> Starting 14-day paper bot"
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml up -d --build
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml ps

echo
echo "Bootstrap complete."
echo "Follow logs with:"
echo "  cd ${MANTEC_DIR}"
echo "  docker compose -f analysis/real_world_testsing/docker-compose.paper.yml logs -f paper_bot"
