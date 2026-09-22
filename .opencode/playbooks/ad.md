# Playbook — AD (Active Directory)
Phases: 1 recon → [CHECKPOINT] → 2 analyze → [CHECKPOINT] → 3 exploit → [CHECKPOINT] → 4 report
Outils par phase:
  1 recon : enum users/groups/SPNs (lab), bloodhound-like mapping si dispo, DNS/DC discovery
  2 analyze : kerberoastable/asrep analysis, ACL paths, attack-path ranking
  3 exploit : AS-REP roasting checks, delegation abuse — UNIQUEMENT lab AD isolé
  4 report : validate_finding.sh gate, findings.md avec chemin complet, report-writer
Critères de sortie:
  1→2 : topologie + identités
  2→3 : chemin le plus court documenté avec falsifier
  3→4 : findings validés ou non (preuve obligatoire)
Checkpoints: STOP + ping opérateur après chaque flèche. Toujours lab isolé.
