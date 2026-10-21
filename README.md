# redteam-agent

Agent de sécurité offensif autonome, piloté par mission en langage naturel. Il orchestre des outils open source (recon, scanning, enum, exploitation) dans une session conteneurisée, en gardant un humain dans la boucle.

> ⚠️ Usage strictement réservé à des environnements **autorisés** (lab, pentest contractualisé). L'opérateur est responsable de la conformité de chaque engagement.

## Principes

- **Mission → exécution** : une consigne naturelle se traduit en plan d'actions (recon, scan, enum, exploit, pivot, report).
- **Sandbox** : chaque étape tourne dans une cage restreinte (nftables, proxychains, édition de fichiers confinée).
- **Garde-fous** : régime passif par défaut ; toute action offensif exige un `oui` explicite de l'opérateur.
- **Traçabilité** : chaque commande est loggée ; rapport de fin d'engagement.
- **Anonymat contrôlé** : proxy chaîné configurable (voir `references/README-anonymat.md` et `README-nftables.md`).

## Structure

- `.opencode/commands/` — commandes métier (recon, scan, enumerate, exploit, pivot, osint, report…)
- `.opencode/playbooks/` — playbooks par cible (webapp, api, network, cloud, ad)
- `.opencode/prompts/agents/` — rôles spécialisés (recon, fuzzer, exploit-developer, report-writer…)
- `.opencode/references/` — doctrine (anonymat, secrets, cage)
- `.opencode/plugins/` — hooks d'engagement
- `references/offensive-tactics/` — taxonomie de tactiques (référence, ne s'exécute pas)

## Démarrage

1. Configurer le provider d'agent (opencode) et le runtime sandboxé.
2. Contrôles : `scripts/opsec-check.sh` (egress OPSEC, fail-closed) et
   `scripts/check_benchmark.sh <engagement_dir>` (intégrité findings + coverage surfaces).
3. Lancer une mission dans une session cage : `engage` (ou `autoengage`) avec la cible et le scope.

## Limites honnêtes

- Pas de chiffrement automatique des secrets côté agent : hygiène locale documentée (permissions 600, refus argv, guard pre-write) — voir `.opencode/references/SECRETS.md`.
- Le pool d'outils dépend de ce qui est installé dans la cage ; un outil absent produit un refus nommé, pas un échec silencieux.
- L'anonymat n'est garanti que dans la configuration proxychains/nftables documentée ; l'opérateur reste seul juge du périmètre autorisé.

## Licence

Usage interne / projet personnel. Contenu à caractère technique offensif à destination de professionnels de la sécurité.
