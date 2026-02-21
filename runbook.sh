#!/usr/bin/env bash
set -euo pipefail

MANTEC_DIR="${MANTEC_DIR:-/opt/mantec}"
COMPOSE_FILE="analysis/real_world_testsing/docker-compose.paper.yml"

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  start    Start paper stack
  logs     Follow paper bot logs
  status   Show container status
  stop     Stop stack
  restart  Rebuild and restart stack
EOF
}

cmd="${1:-}"
if [[ -z "${cmd}" ]]; then
  usage
  exit 1
fi

cd "${MANTEC_DIR}"

case "${cmd}" in
  start)
    docker compose -f "${COMPOSE_FILE}" up -d --build
    ;;
  logs)
    docker compose -f "${COMPOSE_FILE}" logs -f paper_bot
    ;;
  status)
    docker compose -f "${COMPOSE_FILE}" ps
    ;;
  stop)
    docker compose -f "${COMPOSE_FILE}" down
    ;;
  restart)
    docker compose -f "${COMPOSE_FILE}" down
    docker compose -f "${COMPOSE_FILE}" up -d --build
    ;;
  *)
    usage
    exit 1
    ;;
esac
