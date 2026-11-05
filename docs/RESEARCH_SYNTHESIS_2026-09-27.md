# Synthèse veille — guardrails & benchmarks agent redteam (2026-09-27)

> Lecture seule, aucun impact sur session OpenCode PID 7850/7853, Wi-Fi, lid-keep-awake.
> Sources fetch : arXiv 2609.16694 (HTML complet), 2510.03610 (HTML complet), WSTG 4.2 + WSTG Testing Framework, SysReptor docs, 2x 404 (APTS officiel & PWNBench GitHub — fallback).

## 1. OWASP WSTG 4.2 — cadre normatif applicable

- **Authorization first (Scope Authority).** `scope.json` seul fait foi, écrit par l'opérateur humain. Si cible ambiguë (hostname → service tiers, IP publique), signaler et ne poursuivre QUE la part non-ambiguë. Déjà dans `operator-core.md` / `AGENTS.md`.
- **Testing as bug-finding, pas checklist.** WSTG : "techniques, not a checklist" + "DAST/SAST give breadth, this guide gives depth". Traduction agent : wordlists ≤500 inline, escalade `fuzzer` seulement sur `stage=fuzz_pending`.
- **Phase gates.** 5 phases SDLC + Testing Framework imposent un checkpoint avant chaque famille (Information Gathering → Config → … → Injection). Chez nous : `operator_status.sh` + `graph.json` intents ouverts.
- **Ce que WSTG n'impose PAS mais que l'agent doit ajouter** : DNS/IP enforcement fail-closed, allowlist réseau, logging opposable, rate ceiling.

Règles normatives dérivées :
1. **Allowlist stricte** : `scope.json {hostname, hosts[], ips[], domains[], outOfScope[]}` seule source. Tout `fetch`/`nmap`/`ffuf` passe `reconcile_surface_coverage.sh`.
2. **Hard-fail hors scope** : `egress-wrap.sh` / `opsec_guard.sh` refusent (exit 1) si `rt_og_verdict ∈ {CLAIR, INCONNU}` — à étendre à tous les wrappers MCP.
3. **Logging opposable** : `log.md` + `graph.json` + `findings.md` + `cases.db` + tag `[ATT&CK: Txxxx]` (`ATTACK_MAP.md` 17 techniques).
4. **Rate ceiling ≤10 rps** : `verify-tor.sh` §9 vérifie `container.sh`.

## 2. ROE Gate — DNS/IP enforcement fail-closed

Pas de standard "ROE Gate" publié sous ce nom à l'URL (404 APTS). Pattern recommandé et déjà partiellement implémenté :

- **DNS gate** : toute résolution hors `scope.json` → refus. Chez nous : `99-pentest-dns.conf` (Quad9 filtrant + Cloudflare) + `DNSOverTLS=opportunistic` + `DNSSEC=allow-downgrade` dans `zz-vpn-compat.conf`. `strict` causait blackout car `nft inet windscribe` drop `53 → 1.1.1.1/9.9.9.9/149.112.112.112/192.168.1.254` (seul `10.255.255.1` restait sans DoT).
- **IP gate** : `vpn_state.sh` double signal (dernière ligne `État de connexion` + preuve matérielle `tun/utun/wg/ppp/xfrm` + `rt_wg_manual_up` handshake <180s). `RT_VPN_TRUST_CLI=1` échappatoire diagnostic seule.
- **Fail-closed** : `vpn-up.sh` exit 2 si tunnel sans `fetch_egress_ip()` vérifiée (double sonde `api.ipify.org` → `1.1.1.1/cdn-cgi/trace` sans DNS) ; `stop_helper` auto sur échec 45s.
- **Recommandation** : figer en `lib/roe_gate.sh` (`rt_roe_allow host|ip → 0/1`) sourcée par `dispatcher.sh`, `browser_flow.py`, `mcp_*.sh` — pas seulement wrappers shell.

## 3. arXiv 2609.16694 — Guardrails for AI Pentest Agents (NIT Calicut, 15 Sep 2026)

### Threat taxonomy (section 5)

- **LLM-lifecycle (5.1)** : pre-training poisoning, fine-tuning jailbreak, inference-time prompt injection / indirect via tool output.
- **Agent-architecture (5.2)** :
  - *Memory/Knowledge (5.2.1)* : poisoning `MEMORY_DAG.md`, RAG poisoning, persistance de raisonnement faux.
  - *Multi-agent (5.2.2)* : communication poisoning, inter-agent prompt injection, debate manipulation — 1 agent compromis propage via `task`/`handoff`.
  - *Tool/Execution (5.2.3)* : metadata poisoning d'outils, MCP servers malveillants, workflow manipulation, command injection via sortie d'outil.
- **Hybrid (5.3)** : combinaisons (tool output → memory → coordination).

### Trust boundaries (4.2)

LLM boundary, Memory boundary, Execution boundary (LLM action → tool/API), Coordination boundary (agent ↔ agent).

### Guardrails G-A à G-F (section 7)

| Guardrail | Ancrage chez nous |
|---|---|
| G-A Pre-training | hors scope (fournisseur modèle) |
| G-B Fine-tuning/Alignment | `operator-core.md` FRAME OVERRIDE pos 1 + `check_operator_prompt_contract.py` |
| G-C Inference-time | `check_egress_contract.sh`, `check_operator_respawn_contract.py`, `update_phase_from_stages.sh` (T05 gate) |
| G-D Memory/Knowledge | `MEMORY_DAG.md` falsifier + `intel_changed_check.sh` high-water mark |
| G-E Multi-agent | `dispatcher.sh` + `parallel_dispatch.sh` — ajouter validation `handoff` schema + isolation canaux, pas d'eval de sortie d'outil |
| G-F Tool/Execution | `lib/vpn_state.sh` + `lib/opsec_guard.sh` + `lib/container.sh` + `proxychains-redteam.conf` + `verify-tor.sh` |

Gaps du papier nous concernant : guardrails chat ≠ agents long-horizon avec mémoire persistante + tool use ; besoin de guardrails **context-aware** et **architecture-aware** (exactement notre `opsec_guard` par mesure vs promesse).

## 4. arXiv 2510.03610 — PentestMCP (Ezetta & Feng, Portland State, NSF 2335633)

- **Idée** : découpler agent ↔ outils via **Model Context Protocol (MCP)** en RPC. Au lieu d'outils cablés, des **MCP servers** exposent prompts/tools/knowledge à chaud.
- **Tâches** : network scanning & fingerprinting, resource enumeration, vulnerability scanning, exploitation, post-exploitation — en kill-chain (chez nous `ATTACK_MAP.md` + `playbooks/{webapp,network,api,ad,cloud}.md`).
- **Lib** : serveurs MCP pour nmap, nuclei, pd-tools, Metasploit RPC, etc. Agent compose à l'exécution. Nous avons déjà 11 MCP dans `opencode.jsonc` + `check_metasploit_runtime.sh` + `mcp_obscura.sh`/`mcp_playwright.sh` wrappés par `egress-wrap.sh`.
- **Évaluations** : CVE-2017-5638 (Struts) + CVE-2017-0144 (EternalBlue) rejouées (setup + scanning + exploitation + post-exploitation) + comparaisons inter-modèles. Code `github.com/Craftzman7/pentest-mcp`. Harness branchable tel quel, wrappers restent valides.

## 5. SysReptor — reporting

- **Produit** : Markdown → PDF via HTML designer, collab temps réel, versioning.
- **API Python** : `Projects`, `Notes`, `Finding Templates`, `Project Designs`, `Importers` (Burp, Nessus, Qualys, OpenVAS, Nmap, SSLyze, ZAP). Endpoints `CreateProject/PushProject`, `FindingFromTemplate/ExportFindings`.
- **Usage agent** : `compose_partial_report.sh` + `finalize_engagement.sh` → push `findings.md` vers SysReptor via `FindingFromTemplate` (31 challenges `benchmark/ground-truth.json` déjà alignés Juice Shop). `benchmark/run_local.sh` + `score_benchmark.sh` = harness local avant push.

## 6. PWNBench (CyberArk) — 404, fallback

Repo `github.com/cyberark/PWNBench` inaccessible (404/privé). D'après publications CyberArk :
- **Objectif** : benchmark LLM en offensive security (CTF, exploit dev, privesc, AD).
- **Métriques** : success rate/tâche, tentatives, temps, coût tokens, faux positifs, coverage ATT&CK. Proche de `benchmark/ground-truth.json` (31 challenges) + `score_benchmark.sh` (précision/rappel/F1) + `check_benchmark.sh` (refus non-loopback, gates intégrité/couverture).
- **Recommandation** : ne pas dupliquer ; brancher `benchmark/run_local.sh` (Juice Shop loopback-only, `internal:true`) comme harness PWNBench-compatible.

## 7. Lecture transverse — manques à combler

- **DNS gate** non centralisé (dispersé `vpn_state.sh` / `opsec_guard.sh` / `resolved.conf.d/`) → factoriser en `lib/roe_gate.sh`.
- **MCP trust** : aucun pinning/signature des MCP servers (G-F) → allowlist SHA + JSON schema validation `opencode.jsonc`.
- **Memory poisoning** : `MEMORY_DAG.md` falsifier existe mais pas de garde anti-injection via `intel.md` / tool output → sanitizer avant `append_*`.

