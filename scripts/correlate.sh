#!/usr/bin/env bash
# correlate.sh <findings.jsonl> — corrélation multi-outils (T11 copilot v2).
# Dédup par clé host:port:CVE. Confiance : 2+ sources = 100, 1 = 50, 0 = 0 (jamais sorti).
# Sortie : JSONL correlé avec sources=[...] sur stdout.
set -u

F="${1:-}"
[ -z "$F" ] && { echo "usage: correlate.sh <findings.jsonl>" >&2; exit 2; }
[ -f "$F" ] || { echo "introuvable: $F" >&2; exit 2; }

jq -s '
  map(select(.host != null and .port != null and .cve != null))
  | group_by(.host + ":" + (.port|tostring) + ":" + .cve)
  | map(
      (map(.source) | unique) as $src
      | (if ($src|length) >= 2 then 100 elif ($src|length) == 1 then 50 else 0 end) as $conf
      | {
          key: (.[0].host + ":" + (.[0].port|tostring) + ":" + .[0].cve),
          host: .[0].host,
          port: .[0].port,
          cve: .[0].cve,
          sources: $src,
          confidence: $conf,
          title: .[0].title
        }
    )
  | map(select(.confidence > 0))
  | .[]
' "$F"
