# Playbook — CLOUD
Phases: 1 recon → [CHECKPOINT] → 2 analyze → [CHECKPOINT] → 3 exploit → [CHECKPOINT] → 4 report
Outils par phase:
  1 recon : enum buckets/instances/roles (osint + creds lab), metadata endpoints
  2 analyze : IAM policy review, privilege escalation paths, SSRF→metadata hypotheses
  3 exploit : least-impact proof (read-only proof preferred, write tests sur comptes sandbox lab)
  4 report : validate_finding.sh gate, findings.md, report-writer
Critères de sortie:
  1→2 : inventaire ressources + rôles
  2→3 : chemin d'élévation démontré ou réfuté
  3→4 : findings validés
Checkpoints: STOP + ping opérateur après chaque flèche. Comptes sandbox uniquement.
