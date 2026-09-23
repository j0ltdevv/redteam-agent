# Benchmark local style EthiBench — cibles Docker vulnérables contrôlées

Cible unique pour commencer : Juice Shop (déjà câblée dans `finalize_engagement.sh`).
Aucun outil ajouté. Doctrine `/engage` intacte : le harness est un wrapper autour.

## Fichiers

| Fichier | Rôle |
|---|---|
| `benchmark/docker-compose.benchmark.yml` | Cible loopback-only, réseau `internal: true` |
| `benchmark/run_local.sh` | Harness : `up` / `status` / `score <eng_dir>` / `down` |
| `benchmark/ground-truth.json` | 31 challenges repris du guard `finalize_engagement.sh` |
| `scripts/score_benchmark.sh` | Précision / rappel / F1 depuis `findings.md` |
| `scripts/check_benchmark.sh` | Refus non-loopback + gates intégrité et couverture |

## Run (~60 min la 1re fois avec pulls, ~30 min ensuite)

1. `benchmark/run_local.sh up` (~2 min, image en cache — affiche l'URL avec l'IP conteneur)
2. Dans OpenCode : `/engage --auto http://<ip-conteneur>:3000` (URL donnée par l'étape 1)
3. `benchmark/run_local.sh score engagements/<dir>` (~2 min : finalize + vérif + score)
4. `benchmark/run_local.sh down`

## Interdits

Cibles publiques, bounty, pentest non autorisé : `check_benchmark.sh` refuse
toute cible non-loopback (exit 2). Le réseau `internal: true` coupe l'egress
de la cible (pas de reverse-shell sortant).
