# Playbook — API
Phases: 1 recon → [CHECKPOINT] → 2 analyze → [CHECKPOINT] → 3 exploit → [CHECKPOINT] → 4 report
Outils par phase:
  1 recon : enumeration endpoints (OpenAPI/swagger, JS routes, katana), auth schema discovery
  2 analyze : idor-testing, jwt-testing, business-logic, graphql introspection, rate-limit probes
  3 exploit : crafted requests (curl), session/token abuse, mass-assignment chains
  4 report : validate_finding.sh gate, findings.md (incl. business-logic evidence), report-writer
Critères de sortie:
  1→2 : surface API complète (routes, params, auth)
  2→3 : hypothèses IDOR/logique/JWT testées avec falsifiers
  3→4 : findings validés (2 sources) ou unconfirmed
Checkpoints: STOP + ping opérateur après chaque flèche.
