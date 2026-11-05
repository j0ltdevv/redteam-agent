# Proposals ranked — add-ons redteam-agent (2026-09-27)

> Aucun changement live sur session OpenCode 7850/7853. Tout est proposé, pas appliqué. Ordre = priorité.

## P0 — déjà fait, à conserver

| # | Quoi | Statut |
|---|---|---|
| P0.1 | `vpn-up.sh --check/--diagnose/--down` + `ensure_helper/stop_helper/down` + `fetch_egress_ip` double sonde + `firewall_state` | DONE 2026-09-27, validé `--check→--down` (helper inactive, pas de `nft inet windscribe`, DNS 9/9) |
| P0.2 | `99-anon.conf stable+${CONNECTION}` + `99-pentest-dns.conf` source unique + `anonymat.conf` neutralisé | DONE `netfix-20260927-112525` (fix 5 507 ETIMEOUT) |
| P0.3 | `windscribe-helper` disabled + `app-windscribe@autostart.service` masked + `windscribe.desktop.disabled` + `nft inet windscribe` supprimée | DONE `windscribe-off` |
| P0.4 | Bulle `pentest-vpn v2` (wg0 DANS netns, kill-switch structurel, DNS `10.2.0.1` via wg0) | DONE 2026-09-25, vérifié 7 OK/5 KO bulle, 12 OK/0 KO hôte |

## P1 — quick wins (≤1h, impact fort, sans toucher session)

| # | Proposal | Impact | Effort | Détails |
|---|---|---|---|---|
| 1 | **Fix `check_egress_contract.sh` faux positif `opencode.json`** — tester `opencode.jsonc` | évite 1 FAIL bruit masquant vraie régression | 10 min | `re.sub(r"^\s*//.*$","",open("opencode.jsonc").read(),flags=re.M)` + grep `9050` |
| 2 | **`lib/roe_gate.sh` centralisé** — `rt_roe_allow host|ip→0/1` allowlist `scope.json` + CIDR, sourcé par `dispatcher.sh`, `browser_flow.py`, `mcp_*.sh` | ROE hard-fail partout, pas seulement wrappers | 45 min | DNS gate + IP gate + fail-closed unifiés |
| 3 | **Idem `verify-tor.sh` §7** | cohérence des deux gates | 10 min | même patch que #1 |
| 4 | **`opsec-check.sh` timeout** — `timeout 12` sur `curl ipinfo` (vu 30s timeout) | évite faux INCONNU par lenteur | 5 min | ligne 43 déjà `timeout 12`, généraliser |
| 5 | **Doc `bubble/README.md`** — table env `RT_BUBBLE` & `REDTEAM_RUNTIME_MODE` | évite confusion opérateur | 5 min | déjà dans `redteam-bubble` mais pas README |

## P2 — structurants (1-4h)

| # | Proposal | Impact | Effort | Détails |
|---|---|---|---|---|
| 6 | **MCP trust (G-F)** — allowlist SHA + JSON schema `opencode.jsonc` (`9050` en dur interdit, `proxychains` via `egress-wrap.sh` seul) | bloque MCP malveillant (2609.16694 §5.2.3) | 2h | `scripts/check_mcp_trust.sh` : `jq` + `sha256` + `ajv` |
| 7 | **Memory sanitizer (G-D)** — filtrer `intel.md`/tool output avant `append_*` / `MEMORY_DAG.md` (strip `{{ }}`, `<<<`, `SYSTEM:`) | bloque RAG poisoning (§5.2.1) | 2h | `lib/memory_guard.sh` + hook `intel_changed_check.sh` |
| 8 | **Multi-agent handoff validation (G-E)** — JSON schema `task`/`handoff`, pas d'eval de sortie d'outil, isolation canaux | bloque communication poisoning (§5.2.2) | 3h | `dispatcher.sh` + `parallel_dispatch.sh` |
| 9 | **SysReptor push** — `scripts/push_sysreptor.sh` : `FindingFromTemplate` depuis `findings.md` + `benchmark/ground-truth.json` | reporting opposable | 3h | API `CreateProject`/`ExportFindings` (docs.sysreptor.com) |
| 10 | **PentestMCP branch** — importer `github.com/Craftzman7/pentest-mcp` MCP servers (nmap/nuclei/pd-tools) derrière `egress-wrap.sh` | kill-chain RPC composable | 2h | `opencode.jsonc` + `egress-wrap.sh` déjà prêts |

## P3 — nice-to-have

| # | Proposal | Impact | Effort | Notes |
|---|---|---|---|---|
| 11 | **Rate ceiling bloquant en CI** — `verify_opsec_rate_ceiling` déjà, rendre bloquant `check_benchmark.sh` | doctrine ≤10 rps opposable | 30 min | fail si `-t`/`--rate` >10 |
| 12 | **PWNBench harness** — mapper `score_benchmark.sh` (précision/rappel/F1) vers format PWNBench | benchmark externe | 1h | `benchmark/run_local.sh` reste harness (`internal:true`) |
| 13 | **DoT strict toggle** — `scripts/toggle_dot_strict.sh` (strict seulement si `nft inet windscribe` absente OU DNS `10.255.255.1` DoT-aware) | durcissement DNS si VPN sans drop 53 | 1h | `zz-vpn-compat.conf` switch |
| 14 | **Proxychains/Tor opt-in durci** — doc `remote_dns_subnet` + test `getent hosts` via Tor | évite DNS leak lab→exit | 1h | déjà fail-closed |
| 15 | **Netns généralisée** — `katana_ingest.sh` local dans bulle | 100% trafic framework dans bulle | 3h | `REDTEAM_RUNTIME_MODE=local` déjà |

## Ordre d'exécution recommandé (sans toucher live)

1. **P1 #1 + #3** (10 min, bruit gates) → 2. **P1 #2** (`roe_gate.sh`, 45 min, ROE) → 3. **P2 #6** (MCP trust) → 4. **P2 #7** (memory) → 5. **P2 #8** (multi-agent) → 6. **P2 #9/#10** (SysReptor/PentestMCP) → 7. **P3** au fil de l'eau.

Tous testables en dry-run (`--check/--diagnose`, `check_egress_contract.sh`, `verify-tor.sh`) sans monter de tunnel ni toucher la session OpenCode.
