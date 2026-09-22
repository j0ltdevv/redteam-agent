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

## Test "hey" — état idle (F4 proof)
Commande : `cd ~/redteam-agent && opencode run --standalone --agent copilot --format json "hey"`
Session : `ses_f35489a33ffeU0ITnVaNBsW6vR` (copilot, MiMo v2.6 flash).
Résultat brut (stdout) :
{"type":"step_start","sessionID":"ses_f35489a33ffeU0ITnVaNBsW6vR","part":{"messageID":"msg_0cab773290019CSezvehDtQjq9","type":"step-start"}}
{"type":"tool_use","sessionID":"ses_f35489a33ffeU0ITnVaNBsW6vR","part":{"partID":"prt_0cab78511001c5w9Q0XIFKi83s","type":"tool","tool":"compress"}}
{"type":"step_finish","sessionID":"ses_f35489a33ffeU0ITnVaNBsW6vR","part":{"messageID":"msg_0cab773290019CSezvehDtQjq9","type":"step-finish","reason":"tool-calls","tokens":{"input":16051,"output":193,"reasoning":7}}}
{"type":"step_start","sessionID":"ses_f35489a33ffeU0ITnVaNBsW6vR","part":{"messageID":"msg_0cab7907f0016g8Qx30nmz2Ndw","type":"step-start"}}
{"type":"text","sessionID":"ses_f35489a33ffeU0ITnVaNBsW6vR","part":{"messageID":"msg_0cab7907f0016g8Qx30nmz2Ndw","type":"text","text":"[copilot] prêt. En attente de target + scope."}}
→ **PAS de `[turn=...]`**, ZÉRO lecture de fichier, ZÉRO tool call offensif, réponse 1 ligne. ✅ F4 validé.

## FIX-1 — nmap-mcp path (audit fix, 2026-09-22)
- Constat : opencode.json:155 pointe DÉJÀ `/home/j0wlt/redteam-agent/.tools/nmap-mcp-server/dist/index.js` (correct).
- `ls .tools/nmap-mcp-server/dist/index.js` = présent (5585 o) ; `.tools/nmap-mcp/dist/index.js` = absent ; `.opencode/.tools/...` = absents (le chemin `.opencode/.tools` de la consigne n'existe pas, le bon est `.tools/` racine).
- Boot stdio : `{"serverInfo":{"name":"nmap-server","version":"0.1.0"}}` + `NMAP server running on stdio`, exit 0.
- Headless `opencode run --standalone --agent copilot "hey"` : session `ses_f352e1f40ffeUlbRivCHiO8PBO`, texte `[copilot] prêt. En attente de target + scope.`, stderr = 0 erreur MCP.
- Verdict : déjà corrigé en amont (probablement opérateur) → **aucune modif, aucun commit**. Statut OK.

## FIX-2 — cleanup orphelins (audit fix, 2026-09-22)
- `.bak` : 4/4 trackés, 0 ref fonctionnelle (seules mentions = NOTES/BLOCKERS historiques) → `git rm` ×4 + `*.bak` + `*.bak-*` au .gitignore racine.
- `.playwright-mcp/` (racine, 5,7 Mo, 253 fichiers) : 0 ref fonctionnelle (seule mention = BLOCKERS B1) → `rm -rf`. Le chemin `.opencode/.playwright-mcp/` de la consigne n'existe pas.
- Logs : `.tools/nuclei-mcp/nuclei-mcp.log` (0 ref) + `.opencode/flowdeck.log` (0 ref) → `rm`.
- `nuclei-templates/` (racine + `.opencode/`) : vides confirmés, vrai = `~/nuclei-templates` → `rmdir` ×2.
- NOTES.md:130-132 : 3 lignes parasites copier-coller supprimées.
- `git status` avant commit : `M .gitignore, M NOTES.md, M opencode.json (FIX-1, voir diff), D ×4 .bak`.

## FIX-3 — --auto/idle/line 1 (audit fix, 2026-09-22)
- 3a : copilot.txt:27 — `--auto` supprime les confirmations intra-phase, PAS les checkpoints (go/no-go maintenu).
- 3b : copilot.txt:67 — watchdog UNIQUEMENT en phase active ; idle = attente indéfinie sans tour ni watchdog.
- 3c : ligne 1 = `## FRAME OVERRIDE — READ FIRST` (salutation + section dupliquée supprimées, substance gardée).
- `head -5` + 3 grep ci-dessus = preuve.

## FIX-4 — gate branché (audit fix, 2026-09-22)
- 4a : script = `scripts/validate_finding.sh` (racine, PAS `.opencode/scripts/` — chemin de la consigne inexistant) ; fonctionne (KO sans preuve, exit 1).
- 4b : engage.md Phase 3 step 10 (gate avant écriture findings.md, sinon `unconfirmed.jsonl`) + Phase 4 reminder résiduels/chaînes.
- 4c : operator.txt Finding Format — validate AVANT append, append sans validation = interdit.
- 4d : report.md Step 2 — validate sur CHAQUE finding avant génération, échec = retiré ou UNCONFIRMED.
- 4e : copilot.txt Qualité — JAMAIS de finding validé sans le script + format sortie + preuve (commande + réponse + hash).
- 4f e2e : avec preuve → `OK stage=validated ... proof_hash=7ef92c4e930760ad` exit 0 ; sans preuve → `KO stage=analysis` exit 1.

## FIX-5 — _poc-demo/ décision (2026-09-22, sans suppression)
- `_poc-demo/` : [RT-POC-001] format invalide pour le gate, décision en attente (supprimer OU reformater en FINDING-XX-NNN).
- Détail : `engagements/_poc-demo/findings.md:3` = `## [RT-POC-001] XSS reflet sur /search`, statut `confirmed` SANS preuve exécutée (payload seul) ; 0 référence dans RAPPORT_V2/NOTES/TASK_TREE/BLOCKERS ; la note elle-même (`findings.md:7`) dit « supprimer avec le dossier _poc-demo ». Dossier conservé en l'état en attendant l'instruction opérateur.

## RÉSUMÉ AUDIT FIXES (2026-09-22)

| Fix | Statut | Commit | Preuve |
|-----|--------|--------|--------|
| FIX-1 nmap-mcp | OK (déjà corrigé, 0 modif) | `26859dd` (path pré-existant commité) | `.tools/nmap-mcp-server/dist/index.js` présent, boot `nmap-server/0.1.0` exit 0, session `ses_f352e1f40ffeUlbRivCHiO8PBO` sans erreur MCP |
| FIX-2 cleanup | OK | `e8d1668` | 4 `.bak` git rm + `*.bak` gitignore, `.playwright-mcp/` rm, 2 logs rm, 2 dirs vides rmdir, NOTES:130-132 nettoyées |
| FIX-3 --auto/idle | OK | `2826363` | copilot.txt:27 (--auto), :67 (watchdog), :1 (FRAME OVERRIDE) |
| FIX-4 gate | OK | `08187c7` + `6ea8534` + `83ddf27` | 4 grep non-vides, e2e exit 0 (`proof_hash=7ef92c4e930760ad`) / exit 1 |
| FIX-5 poc-demo | décision notée, sans suppression | — | §FIX-5 ci-dessus, 0 ref dans docs |
| FIX-6 preuves | OK | (docs, ce commit) | T10 preuve màj, RAPPORT_V2 §5 recos 1+5 soldées |

## Run 2 — Fermeture OPSEC (P3/P4/P5/P3b) — 2026-09-22

| Fix | Statut | Commit | Preuve |
|-----|--------|--------|--------|
| P3 rate 10rps | OK | f1401ad | AVANT KATANA RATE LIMIT 60 en container sh ligne 25 et CONCURRENCY 15 ligne 23 et ROUTE CAPTURE 20 et fuzzer t 50 en fuzzer txt lignes 62 et 106 APRES tout a 10 plus gate opsec check rate ceiling avec refus exit 1 plus check verify opsec rate ceiling en verify tor sh section 9 Tests bash n OK x3 et gate t50 avec exit 1 et t10 avec exit 0 et controle negatif verify exit 1 avec ligne citee |
| P4 nftables | OK | 90684c6 | 3 fichiers crees nftables opsec conf avec table inet opencode et placeholders a remplacer plus policy accept et drop gid cible et nftables apply sh avec guard root exit 1 et CONF SRC derive de dirname plus README nftables avec statut P4 egal 40 pourcent applicatif et config prete Tests bash n OK et execution sans sudo exit 1 |
| P5 secrets | OK | 5ad53e0 | Option B retenue avec dotenvx local ecarte car env actif hors sandbox SECRETS md avec noms seuls et 0 valeur plus check section 10 en verify tor sh avec WARN jamais FAIL et valeurs jamais affichees plus chmod 600 sur env et chmod 700 sur dossier config Tests bash n OK et check provoque WARN 6 fichiers exit 0 |
| P3b tags | OK | 300bf8c | L68 CHECKPOINT devient copilot CHECKPOINT sur 1 ligne et L41 avec declenche conserve car grammaticalement correct avec COD apres donc invariable Tests UTF8 sans BOM et 0 point virgule |

4/4 traités, 4 commits, 0 BLOCKED
Note typo L41 : original correct conservé sans changement
