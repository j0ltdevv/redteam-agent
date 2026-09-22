# BLOCKERS

## B1 — Git absent (impacts : règles de commit §0)
- Étape : toutes (commit `type(scope): summary` requis).
- Erreur : `fatal: ni ceci ni aucun de ses répertoires parents ... n'est un dépôt git` depuis ~/redteam-agent.
- Tenté : git status — le projet n'est pas versionné.
- Déblocage : `git init` dans ~/redteam-agent + .gitignore (.env, .tools/) — décision opérateur requise car initialiser un dépôt change l'état du projet.
- Attitude : fichiers modifiés/ créés le restent, commits différés.

## B2 — Test session GUI non faisable (impacts : T14 partiel, T12/T13)
- Étape : validation runtime des plugins (`@mohak34/opencode-notifier`, `shekohex/opencode-pty`) + des 2 nouveaux MCP dans une vraie session OpenCode sur le dossier redteam.
- Raison : pas de lancement GUI/interactif dans cet environnement d'exécution ; les boots MCP isolés passent, mais la compat plugin v2 (LoadError historic) exige un démarrage réel.
- Déblocage : opérateur — ouvrir une session OpenCode dans ~/redteam-agent, vérifier absence d'erreurs plugin au démarrage + apparition des tools nmap-mcp_*/nuclei-mcp_*.
- Attitude : tout le reste de T14 = 5/5 PASS ; ce point reste documenté UNKNOWN.
