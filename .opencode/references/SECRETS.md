# P5 — Secrets : statut et hygiene locale

Statut : P5 = hygiene locale (permissions 600, refus argv, guard pre-write).
Chiffrement non fait (contrainte no-global-install, `.env` hors sandbox).

## Choix documente : OPTION B

OPTION A (dotenvx local) ecartee car :

- le `.env` actif vit hors sandbox (`~/.config/opencode/.env`), le chiffrer
  depuis ce worktree modifierait un fichier hors projet ;
- tout install globale est interdite (`bun add -d` / `npm i -D` locaux
  autorises, jamais `-g`), et le chiffrement dotenvx du fichier hors sandbox
  reste une action humaine, pas un job agent.

Donc : documentation honnete + garde-fous, pas de chiffrement automatique ici.

## Inventaire (NOMS uniquement, jamais les valeurs)

Source : `grep -oE "^[A-Za-z_][A-Za-z0-9_]*" ~/.config/opencode/.env`
(valeurs jamais lues, jamais affichees, jamais commitees).

Constate le 2026-09-22 : 5 noms presents dans `~/.config/opencode/.env` :

- `VYCE_API_KEY` : present
- `EXA_API_KEY` : present
- `TOKENHARBOR_API_KEY` : present
- `OBSIDIAN_BEARER` : present
- `KIRA_API_KEY` : present

Exemple cite dans le ticket (`INTERACTSH_TOKEN`) : absent de ce `.env`
(nom non trouve par le grep ci-dessus).

Regles :

- ne jamais `cat` le `.env`, ne jamais coller une valeur dans un log,
  un rapport, un ticket ou un commit ;
- ne versionner aucun `.env`, `*.env`, `*.pem`, `*.key`
  (deja couvert par le `.gitignore` racine, sans modification P5) ;
- compter les occurrences, jamais afficher les secrets
  (`grep -l` / `wc -l`, pas de `-o`, pas de `cat`).

## Permissions constatees et durcies (constat uniquement)

Autorise par le ticket : `chmod` uniquement, jamais de lecture du contenu.

- `~/.config/opencode/.env` : constate `600` avant, reconfirme `600` apres
  (`chmod 600 ~/.config/opencode/.env` execute, `ls -l` avant/apres
  avec masquage `[0-9a-f]{64,}` -> `[REDACTED]`).
- `~/.config/opencode/` : constate `755` avant, passe a `700` apres
  (`chmod 700 ~/.config/opencode/` execute, `ls -ld` avant/apres).

## Rotation manuelle (humain, hors sandbox)

1. Generer la nouvelle cle cote fournisseur (dashboard officiel uniquement).
2. Editer `~/.config/opencode/.env` a la main, remplacer la valeur,
   sauvegarder.
3. Verifier : `stat -c "%a %n" ~/.config/opencode/.env` -> attendu `600`.
4. Relancer le check P5 : `bash scripts/verify-tor.sh` (section 10 = WARN
   seulement, jamais FAIL).
5. Si un secret a fuite (log, commit, partage) : revoquer cote fournisseur
   AVANT de generer le remplacant, puis repeter les etapes 1-4.

## Procedure dotenvx hors sandbox (humain, optionnelle)

A executer par l humain dans son shell, jamais par l agent :

1. `cd ~/.config/opencode/`
2. Install locale ou binaire sans global :
   `npm i -D @dotenvx/dotenvx` (local au dossier) ou telecharger le binaire
   dotenvx sans `npm i -g`.
3. `npx @dotenvx/dotenvx encrypt -f .env` (cree `.env.encrypted`,
   ne supprime pas `.env` tout seul).
4. Verifier sans exposer de valeur :
   `grep -c "encrypted:" .env.encrypted` doit etre non nul,
   et aucun hex brut ne doit rester visible en clair.
5. Ajouter `.env.keys` au `.gitignore` concerne, restreindre
   `chmod 600 .env.keys .env.encrypted`, puis seulement apres test concluant,
   supprimer ou archiver le `.env` en clair hors git.
6. En cas de doute : rester en OPTION B (permissions + WARN) et ne pas
   chiffrer a l aveugle.
