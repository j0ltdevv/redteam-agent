#!/usr/bin/env bash
# check_benchmark.sh <engagement_dir> — vérification locale hors-ligne + intégrité.
# 1. Garde OPSEC : refuse tout engagement dont la cible n'est PAS loopback.
# 2. Réutilise les gates existants : intégrité findings + couverture surfaces.
# 3. Vérifie cases.db présent (queue traçable).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENG_DIR="${1:?usage: check_benchmark.sh <engagement_dir>}"
SCOPE="$ENG_DIR/scope.json"

[ -f "$SCOPE" ] || { echo "scope.json introuvable dans $ENG_DIR" >&2; exit 1; }

HOST="$(jq -r '.target // empty' "$SCOPE" | python3 -c 'from urllib.parse import urlsplit; import sys; print(urlsplit(sys.stdin.read().strip()).hostname or "")')"
BENCH_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' benchmark-juice-shop 2>/dev/null || true)"
case "$HOST" in
    127.0.0.1|localhost|host.docker.internal)
        echo "[bench] cible loopback OK ($HOST)"
        ;;
    *)
        if [ -n "$BENCH_IP" ] && [ "$HOST" = "$BENCH_IP" ]; then
            echo "[bench] cible benchmark OK ($HOST)"
        else
            echo "[bench] REFUS : cible non-loopback et non-benchmark ($HOST) — benchmark local uniquement" >&2
            exit 2
        fi
        ;;
esac

bash "$SCRIPT_DIR/check_findings_integrity.sh" "$ENG_DIR"
bash "$SCRIPT_DIR/check_surface_coverage.sh" "$ENG_DIR"
[ -f "$ENG_DIR/cases.db" ] || { echo "cases.db manquant dans $ENG_DIR" >&2; exit 1; }
echo "benchmark verification: ok"
