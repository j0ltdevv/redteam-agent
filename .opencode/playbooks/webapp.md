# Playbook — WEBAPP
Phases: 1 recon → [CHECKPOINT] → 2 analyze → [CHECKPOINT] → 3 exploit → [CHECKPOINT] → 4 report
Outils par phase:
  1 recon : whatweb, httpx-like fingerprints, ffuf dirbust, katana crawl, source-analyzer (JS/routes)
  2 analyze : nuclei templates, wstg-pentest checks, manual curl probes, MEMORY_DAG hypotheses
  3 exploit : sqlmap, xss probes, custom payloads via run_tool, interactsh OOB (blind), caido replay
  4 report : validate_finding.sh gate, findings.md, ATTACK tags, report-writer subagent
Critères de sortie de phase:
  1→2 : surfaces listées + tech stack connu
  2→3 : chaque hypothèse a un falsifier + test exécuté
  3→4 : chaque finding validé stage-6 OU classé unconfirmed
Checkpoints: STOP + ping opérateur après chaque flèche.
