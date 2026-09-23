#!/usr/bin/env bash
# run_local.sh — harness benchmark local, wrapper autour d'/engage (doctrine intacte).
# Usage :
#   benchmark/run_local.sh up                → démarre les cibles + attend le healthy
#   benchmark/run_local.sh status            → état conteneurs + snapshot challenges
#   benchmark/run_local.sh score <eng_dir>   → finalize + vérif + score (après /engage)
#   benchmark/run_local.sh down              → arrête les cibles
#
# Le run /engage lui-même reste opérateur : après `up`, lancer dans OpenCode
# (l'URL exacte avec l'IP conteneur est affichée par `up`) :
#   /engage --auto http://<ip-conteneur>:3000
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
COMPOSE_FILE="$BENCH_DIR/docker-compose.benchmark.yml"
TARGET_URL="${BENCH_TARGET_URL:-}"
CMD="${1:-help}"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

# Résout la cible via l'IP conteneur (aucun port publié sur réseau internal).
# BENCH_TARGET_URL explicite = override (ex. debug), sinon IP benchmark-juice-shop.
resolve_target() {
    if [ -n "$TARGET_URL" ]; then return 0; fi
    local ip
    ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' benchmark-juice-shop 2>/dev/null || true)"
    [ -n "$ip" ] || { echo "[bench] KO : IP conteneur introuvable (conteneur démarré ?)" >&2; exit 1; }
    TARGET_URL="http://${ip}:3000"
}

cmd_up() {
    compose up -d
    resolve_target
    echo "[bench] cible = $TARGET_URL"
    echo "[bench] attente healthy sur $TARGET_URL/api/Challenges (180s max)"
    for i in $(seq 1 180); do
        if curl -sf --max-time 3 "$TARGET_URL/api/Challenges" >/dev/null 2>&1; then
            echo "[bench] cible OK après ${i}s — lance : /engage --auto $TARGET_URL"
            return 0
        fi
        sleep 1
    done
    echo "[bench] KO : cible injoignable après 180s" >&2
    compose logs --tail 30
    exit 1
}

cmd_status() {
    resolve_target
    compose ps
    echo "---"
    python3 - "$TARGET_URL" <<'PY'
import json, sys
from urllib.request import urlopen
from urllib.parse import urljoin
base = sys.argv[1].rstrip('/') + '/'
try:
    with urlopen(urljoin(base, 'api/Challenges'), timeout=5) as r:
        items = json.load(r).get('data', [])
    solved = sum(1 for c in items if isinstance(c, dict) and c.get('solved'))
    print(f"challenges: {solved}/{len(items)} solved")
except Exception as e:
    print(f"snapshot indisponible: {e}")
PY
}

cmd_score() {
    ENG_DIR="${2:-}"
    [ -n "$ENG_DIR" ] || { echo "usage: run_local.sh score <engagement_dir>" >&2; exit 1; }
    [ -d "$ENG_DIR" ] || { echo "dossier introuvable: $ENG_DIR" >&2; exit 1; }
    echo "=== 1/3 finalize ==="
    bash "$REPO_ROOT/scripts/finalize_engagement.sh" "$ENG_DIR"
    echo "=== 2/3 verification ==="
    bash "$REPO_ROOT/scripts/check_benchmark.sh" "$ENG_DIR"
    echo "=== 3/3 scoring ==="
    bash "$REPO_ROOT/scripts/score_benchmark.sh" "$ENG_DIR" "$BENCH_DIR/ground-truth.json"
}

cmd_down() { compose down; }

case "$CMD" in
    up) cmd_up ;;
    status) cmd_status ;;
    score) cmd_score "$@" ;;
    down) cmd_down ;;
    *) echo "usage: run_local.sh {up|status|score <eng_dir>|down}" >&2; exit 1 ;;
esac
