# NOTES — copilot v2 (digests + vérifications)

## Digests contexte (§2)

### 1. prompts/agents/copilot.txt (v1 lu avant remplacement ; v2 en place)
- v1 (52 lignes) : 3 modes (autonome défaut / manuel / agressif), règles "NEVER ask", scope 1 ligne.
- Point faible : aucune falsification, aucun budget, aucune mémoire persistante.
- v2 (92 lignes) : checkpoints [CHECKPOINT], pipeline 6 étapes, task tree .cockpit/tasktree.md, corrélation 2 outils, posture MiMo anti-confabulation, ≤10 rps.
- Sauvegarde : prompts/agents/copilot.txt.v1.bak.
- Aucun finding sans exécution réelle de preuve.

### 2. opencode.json (13206 octets)
- model = opencode/mimo-v2.6-flash-free (confirmé dispo via `opencode models | grep mimo`), small = nvidia/gemma-4-31b-it.
- 9 MCP : metasploit, hexstrike, interactsh(enabled:false), sec-toolkit, obscura, playwright, wstg-pentest, osint, caido.
- instructions = 31 skills SKILL.md + INSTRUCTIONS.md + references/INDEX.md (tout injecté à chaque session = charge).
- agents : copilot + operator (primary) + 7 subagents ; 19 commandes ; permission Read/Glob/Grep allow, skill using-superpowers deny.
- Fichier = JSONC (commentaires // ligne 117+) : jq pur échoue, il faut strip des commentaires.

### 3. prompts/agents/operator.txt
- Lead operator : core loop ASSESS→DECIDE→PLAN→PRESENT→DISPATCH→RECORD→LOOP.
- Gère cases.db / dispatcher / surfaces.jsonl / intel respawn, stop-reason format, banners interdits en run autonome.
- Ne teste jamais directement (pas de curl) : dispatch subagents uniquement.

### 4. skills/*/SKILL.md (31 skills sous ~/redteam-agent/skills/, pas .opencode/)
- Chemins dans opencode.json relatifs à la racine ~/redteam-agent/ (skills/, references/INDEX.md existent).
- 31 skills méthodo : sqli, xss, ssrf, idor, jwt, graphql, cors, smuggling, race, business-logic, lfi, ssti, cmdi, xxe, deserial, file-upload, websocket, info-disclosure, subdomain, user-enum, open-redirect, osint, sensitive-data, report, source-analysis, auth-bypass, port-scan, dir-fuzz, param-fuzz, web-recon.
- Frontmatter YAML (titre après "---"), pas de titre H1 ligne 1.
- INDEX : ~/redteam-agent/references/INDEX.md présent.

### 5. commands/*.md (19 commandes, pas 18)
- auth, autoengage, config, confirm, engage, enumerate, exploit, osint, pivot, proxy, queue, recon, report, resume, scan, status, stop, subdomain, vuln-analyze.

### 6. DOSSIER_DE_CONTEXTE.md — ABSENT
- Le dossier de contexte a été écrit ailleurs : ~/Documents/Default Project/copilot-contexte-total.md (hors sandbox, lecture seule).

## Vérifications

### T01 — critère d'acceptation
- Attention : la clé réelle est `.agent.copilot.description` (singulier), le critère du plan disait `.agents` (pluriel) → UNKNOWN mineur documenté, clé corrigée utilisée.
- Commande : `sed 's|^[[:space:]]*//.*$||' opencode.json | jq -r '.agent.copilot.description'`
- Sortie : "Autonomous red team copilot with phase checkpoints. Executes recon, analysis, exploitation, and reporting. Pings operator for go/no-go between phases. Never asks for confirmation within a phase."
- model : opencode/mimo-v2.6-flash-free | small_model : nvidia/gemma-4-31b-it (cohérent, mimo confirmé dans `opencode models`).
- Résultat : OK.

## Candidats plugins (T08/T12)
- opencode-notifier : candidat push checkpoint — voir T12.

## T02 — interactsh réparé
- Binaire reconstruit : GOBIN=/home/j0wlt/redteam-agent/.tools/interactsh go install .../interactsh-client@latest → exit 0, 42 Mo.
- Symlink réparé : ~/.local/bin/interactsh-client → .tools/interactsh/interactsh-client.
- Version : Current Version 1.3.1.
- .env local : .opencode/.interactsh.env (INTERACTSH_SERVER=oast.pro, LOG_LEVEL=INFO) + gitignore.
- Config : enabled=true, environment.INTERACTSH_SERVER="oast.pro" littéral.
- UNKNOWN : INTERACTSH_TOKEN — compte oast non configuré ; valeur {env:INTERACTSH_TOKEN} laissée, serveur public oast.pro sans token reste utilisable (rate-limit partagé).
- interpsh-mcp : symlink pipx intact (venv/interactsh-mcp).

## T03 — lazy-load skills
- Avant : 183113 octets injectés/session (31 SKILL.md + INSTRUCTIONS + INDEX).
- Après : 26905 octets (INSTRUCTIONS.md + skills/INDEX.md 3532o + references/INDEX.md) = 14,7% de v1.
- Critère ≤15% : OK.
- skills/INDEX.md généré : 1 ligne/skill, description depuis frontmatter (champ description, pas title — frontmatter = name/description/origin).
- copilot.txt : section CONTEXT ECONOMY mise à jour (lecture skills/<nom>/SKILL.md à la demande).
- Remarque : config listait 31 skills, disque = 31 dossiers, aucune perte.

## T05 — gate déterministe
- scripts/validate_finding.sh créé (chmod +x), 6 stages : inventory/analysis/sanity_check/ruling/feasibility/validated.
- Preuve réelle = evidence.command + output + expect_regex + sha256 preuve ; ruling = 2 sources min.
- Tests : bidon sans preuve → exit 1 (KO sanity_check) ✅ ; complet 2 sources → exit 0 (proof_hash b8116326…) ✅ ; 1 source → exit 1 (KO ruling unconfirmed) ✅.
- copilot.txt : HARD GATE ajouté — interdiction de présenter un finding sans le script, formats [VALIDATED]/[UNCONFIRMED].

## T06 — ATT&CK
- .opencode/ATTACK_MAP.md : 17 techniques (TA0043/TA0002/TA0003/TA0004/TA0006/TA0008…).
- prompt : section KILL CHAIN impose le tag [ATT&CK: Txxxx] sur chaque étape.

## T07 — playbooks
- .opencode/playbooks/{webapp,network,api,ad,cloud}.md créés, format homogène : phases, outils/phase, critères de sortie, checkpoints.
- prompt : chargement .opencode/playbooks/<type>.md au début d'engagement.

## T08 — checkpoints
- Format exact imposé : [copilot][CHECKPOINT] phase=<nom> status=<ok|ko> findings=<v/total> next=<action> go/no-go ?
- Seule pause point ; zéro re-confirmation dans une phase. opencode-notifier = candidat push (T12).

## T09 — budget
- [turn=N/50] sur chaque sortie ; N=M → BUDGET EXHAUSTED stop ; 3 tours sans tool → WATCHDOG stop ; /stop kill switch.

## T10 — frame override
- Paragraphe FRAME OVERRIDE en 1re position de copilot.txt (head -5 vérifié).

## T11 — corrélation
- scripts/correlate.sh : jq group_by host:port:cve ; 2+ sources → confidence 100, 1 → 50, 0 → jamais sorti (filter >0).
- Test : nuclei+sqlmap → 100 ✅ ; nmap seul → 50 ✅ ; exit 0.

## T12 — plugins candidats (5/5 évalués, séquentiel)
1. opencode-notifier (mohak34) — KEEP. Prérequis Linux OK : notify-send 0.8.8 + paplay + bus /run/user/1000/bus. Ajouté au plugin[] projet (jamais `plug -g`).
2. opencode-agent-skills (joshuadavidthomas) — DROP. Le README lui-même : "OpenCode now includes first-party support... this plugin is no longer necessary" (maintenance mode).
3. opencode-mem (tickernelz) — DROP. Mémoire vectorielle locale = système #2 face à Basic Memory/Obsidian déjà branchés + téléchargement embedding model huggingface = surface/surprise.
4. opencode-pty (shekohex) — KEEP. Background processes = msfrpcd/interactsh listeners/mitmproxy de lab ; respecte permissions bash ; auto-cleanup fin de session. UNKNOWN mineur : compat v2 non prouvée avant lancement réel (test T14).
5. opencode-scheduler (different-ai) — DROP. Runs systemd automatiques "even when you're away" = contredit le mode checkpoints (humain go/no-go entre phases) + surface systemd. Revisit en v3 si besoin de /autoengage de fond.
- Commits différés : B1 (pas de dépôt git).

## T13 — MCP candidats (checklist Appsecco : injection output / tool shadowing / secrets / RCE locale / path traversal)
1. nuclei-mcp (addcontent/nuclei-mcp, 49★, Go) — PASS avec notes.
   - Pas de shell exec : lib nuclei en-process (ne.LoadTargets, ExecuteNucleiWithOptsCtx) → pas d'injection de commande.
   - Secrets : config.yaml = host 127.0.0.1:3000, aucun secret hardcodé (chemin log Windows "C:/Users/User" = défaut upstream, à surcharger chez nous).
   - Path traversal : filepath.Join(TemplatesDir, file.Name()) sur listing dir = safe ; templateIDs entrée LLM → lecture YAML limitée, impact faible (noté).
   - Output : findings structurés cache, pas d'interprétation shell.
   - Verdict : KEEP (build local .tools/nuclei-mcp).
2. nmap-mcp (PhialsBasement/nmap-mcp-server, 49★, TS) — PASS.
   - execFile (PAS exec/shell) commenté ligne 110 "prevent shell injection" ; whitelist de flags (validateAdditionalFlags) ; zod schema strict (scanType enum, timing 0-5) → tool shadowing/injection bloqués.
   - Secrets : aucun ; deps = @modelcontextprotocol/sdk + zod only.
   - Noté : target passé en argv sans regex — accepté (execFile = argv safe, pas d'option smuggling évident) ; surveiller.
   - npm: package NON publié (mcp-nmap-server 404) → build local requis.
   - Verdict : KEEP (build local .tools/nmap-mcp).
3. pd-tools-mcp (subfinder/httpx/katana) — DROP.
   - Aucun repo maintenu trouvé ("projectdiscovery mcp" = 0 résultat ; subfinder-mcp 0★, mcp-httpx 3★).
   - Alternative retenue : CLIs PD déjà invoqués via run_tool (kube-style) — pas de MCP-tierce non audité.
   - FuzzingLabs/mcp-security-hub = méta-collection Docker 38 serveurs : hors périmètre (docker, non audité ici) → UNKNOWN documenté.
- Suite build/branchement (turn 53-69) : nmap-mcp = bun install + build OK (erreurs zod TS non fatales, dist émis, boot stdio OK) ; nuclei-mcp = go mod tidy OK mais go build KO (`sonic v1.13.3` incompatible Go 1.27 → `go get github.com/bytedance/sonic@latest` + tidy → build OK, binaire 114 Mo).
- Patchs locaux nuclei-mcp : config.go SetDefault logging.path + nuclei.templates_directory (absolus, .tools + ~/nuclei-templates) ; config.yaml upstream chemins Windows → Linux + rate_limit 150→10 (doctrine ≤10 rps) + level debug→info ; dossiers parasites `C:` créés au 1er boot nettoyés.
- Wart résolu : `$?` après pipe = exit de `tail`, pas du build (signalé, correction : log fichier sans pipe) ; 1 relance interrompue ("location shut down") → relancée OK.
- Branchement opencode.json : nmap-mcp = node .tools/nmap-mcp/dist/index.js, nuclei-mcp = binaire .tools (timeout 15000, enabled) → mcp = 11 clés, jq après strip `//` = OK.
- Boot nuclei ×2 cwd (racine projet = cwd OpenCode, clone) : initialize → serverInfo nuclei-scanner/1.0.0, templates corrects, aucun `C:` recréé.

## T14 — non-régression (5/5 PASS)
1. Parse JSONC jq : model=opencode/mimo-v2.6-flash-free, instructions=3, plugin=3, mcp=11, description v2 exacte.
2. Gate : bash -n OK ; finding sans falsifier → `KO stage: analysis`, exit 1.
3. instructions = [.opencode/instructions/INSTRUCTIONS.md, skills/INDEX.md, references/INDEX.md].
4. copilot.txt : CHECKPOINT ×3. 5. BUDGET EXHAUSTED / turn=N/M ×2.
- Non testable ici : session GUI complète (lancement réel) → compat v2 des plugins notifier/pty = UNKNOWN (B2). Scripts gate/correlate vivent dans ~/redteam-agent/scripts/ (pas .opencode/scripts — chemin corrigé pendant le test).
