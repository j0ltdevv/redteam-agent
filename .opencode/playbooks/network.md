# Playbook — NETWORK
Phases: 1 recon → [CHECKPOINT] → 2 analyze → [CHECKPOINT] → 3 exploit → [CHECKPOINT] → 4 report
Outils par phase:
  1 recon : nmap (-sV -sC discovery), masscan quick sweep, run_recon_pipeline quick/stealth
  2 analyze : map services→CVEs, vuln-analyst subagent, osint CVE lookup
  3 exploit : metasploit_* (exploit-developer), hexstrike, credential checks lab-local only
  4 report : validate_finding.sh gate, findings.md, ATTACK tags, report-writer
Critères de sortie:
  1→2 : hosts vivants + services versions
  2→3 : chemins d'attaque priorisés (impact×exploitabilité)
  3→4 : findings validés ou rejetés avec preuve
Checkpoints: STOP + ping opérateur après chaque flèche.
