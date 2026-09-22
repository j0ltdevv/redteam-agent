# TASK_TREE — copilot v1 → v2

## [T01] Corriger la description de l'agent — statut DONE
- Objectif : description v2 + modèle MiMo dans opencode.json
- Critère d'acceptation : description exacte demandée présente, model = opencode/mimo-v2.6-flash-free
- Preuve : NOTES.md §T01 (jq comment-strippé → chaîne exacte + model OK)
- Dépend de : []

## [T02] Réparer interactsh — statut DONE
- Objectif : binaire local + .env local + enabled true
- Critère d'acceptation : interactsh-client -version OK + enabled dans config
- Preuve : Current Version 1.3.1 + jq enabled=true, server=oast.pro
- Dépend de : []

## [T03] Lazy-load des skills — statut DONE
- Objectif : INDEX 1 ligne/skill, retirer les 31 SKILL.md de instructions
- Critère d'acceptation : taille prompt initial avant/après mesurée (wc -c)
- Preuve : 183113 → 26905 octets = 14,7% (NOTES.md T03)
- Dépend de : []

## [T04] DAG de mémoire cible-centré — statut DONE
- Objectif : MEMORY_DAG.md + 3 règles dans copilot.txt
- Critère d'acceptation : fichier existe, format NODE respecté, prompt le dit
- Preuve : MEMORY_DAG.md (984o, 2 nœuds ex.) + section MEMORY DAG dans prompt
- Dépend de : []

## [T05] Gate déterministe validation 6 étapes — statut DONE
- Objectif : scripts/validate_finding.sh, exit 0/1, exécution réelle preuve
- Critère d'acceptation : test finding bidon → exit 1
- Preuve : bidon exit 1 / complet exit 0 / 1src exit 1 (NOTES.md T05)
- Dépend de : []

## [T06] Mapping MITRE ATT&CK — statut DONE
- Objectif : ATTACK_MAP.md + tag [ATT&CK: Txxxx] imposé
- Critère d'acceptation : table existe + tag dans prompt
- Preuve : ATTACK_MAP.md (17 techniques) + section KILL CHAIN dans prompt
- Dépend de : []

## [T07] Playbooks par type — statut DONE
- Objectif : playbooks/{webapp,network,api,ad,cloud}.md
- Critère d'acceptation : 5 fichiers + référence prompt
- Preuve : ls playbooks/ = 5 fichiers homogènes + ref dans phases
- Dépend de : []

## [T08] Checkpoints inter-phases — statut DONE
- Objectif : format ping exact + attente go/no-go + notifier candidat
- Critère d'acceptation : 4 règles dans prompt, plugin en candidat NOTES.md
- Preuve : format [copilot][CHECKPOINT] phase=<nom> status=<ok|ko>… dans prompt
- Dépend de : []

## [T09] Budget de tours + watchdog — statut DONE
- Objectif : [turn=N/50], 3 tours sans tool = stop, /stop kill switch
- Critère d'acceptation : 4 règles dans prompt
- Preuve : section BUDGET + WATCHDOG (turn=N/M, BUDGET EXHAUSTED, WATCHDOG, kill switch)
- Dépend de : []

## [T10] Sursaut cadre coding assistant — statut DONE
- Objectif : paragraphe en 1re position de copilot.txt
- Critère d'acceptation : head -5 le montre
- Preuve : FRAME OVERRIDE restauré en position 1 par FIX-3 (commit 2826363, `head -1` = `## FRAME OVERRIDE — READ FIRST` vérifié ; régression cb6935f corrigée)
- Dépend de : []

## [T11] Corrélation multi-outils — statut DONE
- Objectif : scripts/correlate.sh dédup host:port:CVE
- Critère d'acceptation : test 2 findings sources différentes → confidence=100
- Preuve : nuclei+sqlmap → 100 ; nmap seul → 50 (NOTES T11)
- Dépend de : []

## [T12] Plugins candidats — statut DONE
- Objectif : verdict keep/drop ×5 dans NOTES.md, séquentiel
- Critère d'acceptation : 5 entrées
- Preuve : NOTES.md §T12 — KEEP notifier + pty, DROP agent-skills/mem/scheduler ; plugin[] = 3 entrées
- Dépend de : []

## [T13] MCP candidats checklist Appsecco — statut DONE
- Objectif : verdict ×3 (nuclei, pd-tools, nmap) dans NOTES.md
- Critère d'acceptation : 3 entrées
- Preuve : NOTES §T13 (KEEP×2 DROP×1) + builds locaux OK + branchement opencode.json (mcp=11, jq JSONC OK) + boot ×2 cwd = JSON-RPC initialize OK, templates=/home/j0wlt/nuclei-templates
- Dépend de : []

## [T14] Non-régression lab — statut DONE
- Objectif : 5 points de vérification session factice
- Critère d'acceptation : 5/5 ou BLOCKED documenté
- Preuve : 5/5 — (1) jq JSONC parse OK (model=mimo, instructions=3, plugin=3, mcp=11) (2) gate syntax OK + finding sans preuve → KO stage=analysis exit 1 (3) instructions = 3 entrées INDEX (4) CHECKPOINT ×3 dans prompt (5) BUDGET EXHAUSTED/turn=N/M ×2. Session GUI complète = non testable ici → compat plugins v2 = UNKNOWN (B2)
- Dépend de : [T03, T05, T08, T09]

## [T15] Rapport final RAPPORT_V2.md — statut DONE
- Objectif : couvre T01-T14, UNKNOWN, BLOCKED, commits, v3
- Critère d'acceptation : fichier existe, wc -l > 0
- Preuve : ~/redteam-agent/RAPPORT_V2.md créé (6 sections : synthèse T01-T14 · 4 UNKNOWN · B1/B2 · leçons builds · 5 recos v3 · mode de validation)
- Dépend de : [T01..T14]
