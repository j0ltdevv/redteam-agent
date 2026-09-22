# RAPPORT — Agent copilot v1 → v2

Date : 2026-09-22 · Périmètre : `~/redteam-agent/` uniquement · Statut global : **T01–T15 = 15/15 DONE** (commits différés = B1)

## 1. Synthèse T01–T14 (statut · preuve · écart)

| T | Statut | Preuve | Écart |
|---|---|---|---|
| T01 description + modèle | DONE | jq (strip `//`) : description exacte v2 + `opencode/mimo-v2.6-flash-free` | — |
| T02 interactsh | DONE | `interactsh-client` 1.3.1 local (.tools), `.interactsh.env` gitignoré, `enabled:true`, server `oast.pro` | token = UNKNOWN |
| T03 lazy-load skills | DONE | 183113 → 26905 o/session = **14,7 %** (critère ≤15 %) ; instructions = 3 entrées | — |
| T04 MEMORY_DAG | DONE | `.opencode/MEMORY_DAG.md` (format NODE, 2 ex.) + section prompt | — |
| T05 gate 6 étapes | DONE | `scripts/validate_finding.sh` : bidon→1, complet 2src→0, 1src→1 ; re-test T14 sans preuve→`KO stage=analysis` exit 1 | — |
| T06 ATT&CK | DONE | `.opencode/ATTACK_MAP.md` (17 techniques) + tag `[ATT&CK: Txxxx]` obligatoire | — |
| T07 playbooks | DONE | `.opencode/playbooks/{webapp,network,api,ad,cloud}.md` | — |
| T08 checkpoints | DONE | format `[copilot][CHECKPOINT] phase=… go/no-go ?` unique pause inter-phases | push tel = runtime |
| T09 budget/watchdog | DONE | `[copilot][turn=N/M]`, BUDGET EXHAUSTED, WATCHDOG, `/stop` | — |
| T10 frame override | DONE | `## FRAME OVERRIDE (T10) — READ FIRST` en 1re ligne du prompt | — |
| T11 corrélation | DONE | `scripts/correlate.sh` : 2src→100, 1src→50, 0→filtré | — |
| T12 plugins ×5 | DONE | KEEP `opencode-notifier` + `opencode-pty` ; DROP agent-skills/mem/scheduler ; `plugin[]`=3 | compat v2 = UNKNOWN |
| T13 MCP ×3 | DONE | KEEP nmap-mcp + nuclei-mcp **branchés** (mcp=11, boots JSON-RPC ×2 cwd OK) ; DROP pd-tools ; checklist Appsecco passée | patchs locaux (cf. NOTES) |
| T14 non-régression | DONE | **5/5 PASS** (parse · gate · INDEX 3 · CHECKPOINT ×3 · BUDGET ×2) | session GUI = B2 |

## 2. UNKNOWN (jamais deviné)

1. `INTERACTSH_TOKEN` — non fourni ; reste `{env:INTERACTSH_TOKEN}` dans la config.
2. **Compat v2 des plugins** (`opencode-notifier`, `opencode-pty`) — boots isolés OK, mais validation runtime nécessite une vraie session (B2).
3. `FuzzingLabs/mcp-security-hub` (38 serveurs Docker) — hors périmètre : non audité, non installé.
4. Options clés `nuclei-mcp` : `templateIDs` en entrée LLM → lecture YAML limitée (impact faible, surveiller).

## 3. BLOCKED

- **B1 — git** : ✅ RÉSOLU — repo **privé** `github.com/j0ltdevv/redteam-agent`, branche `main` up to date, commit `00a9eba` (bootstrap, 257 fichiers). Les commits `type(scope): summary` sont maintenant possibles.
- **B2 — test session GUI non faisable ici** : voir `.opencode/BLOCKERS.md` (déblocage : ouvrir une session dans `~/redteam-agent`).

## 4. Épisodes résolus pendant les builds (leçons conservées)

- `$?` après pipe = exit de `tail`, pas du build → vérifications sans pipe + log fichier.
- `sonic v1.13.3` incompatible Go 1.27 → upgrade local `sonic@latest` (dans `.tools/nuclei-mcp` uniquement).
- `config.yaml` upstream = chemins Windows → patchés Linux + `rate_limit 150→10` (doctrine ≤10 rps) ; dossiers parasites `C:` nettoyés.
- Chemin des scripts gate = `~/redteam-agent/scripts/` (pas `.opencode/scripts/`).

## 5. Recommandations v3

1. **`git init`** (B1) puis premier commit `chore(bootstrap): ignore build artifacts`.
2. **Session pilote** : lancer OpenCode sur `~/redteam-agent`, confirmer plugins + tools `nmap-mcp_*`/`nuclei-mcp_*`, laisser un checkpoint go/no-go se déclencher.
3. **Lazy MCP par phase** : actuellement 11 MCP spawns/session — étendre le principe INDEX aux MCP (disable par phase) si le coût de démarrage gêne.
4. **Bench copilot v2** sur le mock R4 (même protocole que mcode/OpenCode v1) pour mesurer l'effet des gardes-fous sur le bruit hors doctrine.
5. Ponts restants : `interactsh` oast déjà OK ; brancher le validate gate dans le pipeline `/engage` (operator) pour que les findings entrants passent systématiquement par les 6 stages.

## 6. Comment valider (opérateur)

```bash
# session pilote (dossier = projet OpenCode)
cd ~/redteam-agent && opencode
# vérifs automatisables sans GUI :
sed 's|^[[:space:]]*//.*$||' .opencode/opencode.json | jq -e '.mcp | length'   # attendu : 11
bash scripts/validate_finding.sh <finding.json>                                 # 0 = validated
```
