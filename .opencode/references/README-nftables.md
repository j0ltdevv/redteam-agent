# P4 — Cage réseau (statut : cage opérationnelle via systemd-run, kernel nft abandonné)

> **Statut P4 : cage opérationnelle via systemd-run, kernel nft abandonné.**
> Les anciens fichiers `nftables-opsec.conf` et `nftables-apply.sh` ont été
> retirés volontairement (voir « Pourquoi l'abandon » ci-dessous).

## Fallback applicatif — toujours actif

- `tor-wrap` fail-closed : exit 1 si pas de proxy, refuse sans proxy.
- Aucun trafic direct sans Tor au niveau applicatif.
- Ce fallback reste actif indépendamment de la cage.

## Méthode RECOMMANDÉE — cage `systemd-run --user --scope` (wrapper fish)

Cage par session, sans sudo, sans toucher le kernel : chaque lancement
d'OpenCode passe par `systemd-run --user --scope` avec `IPAddressDeny=any`
et une allowlist stricte (loopback, lab, DNS).

- Wrapper versionné dans le repo : `.opencode/references/opencode-caged.fish`
- Usage : `opencode-caged [args…]` dans un shell fish.

**Installation (humain uniquement)** : copier le fichier vers
`~/.config/fish/functions/opencode-caged.fish` :

```fish
cp .opencode/references/opencode-caged.fish ~/.config/fish/functions/opencode-caged.fish
```

> ⚠️ Le repo ne touche **jamais** `~/.config/` — la copie est faite par
> l'humain, à la main.

### Allowlist appliquée par le wrapper

| Destination | Raison |
|---|---|
| `127.0.0.0/8` | loopback (MCP, services locaux) |
| `192.168.56.0/24`, `10.0.0.0/8`, `172.21.0.0/16` | pentest lab isolé |
| `1.1.1.1`, `9.9.9.9` | DNS approuvés |
| tout le reste (`IPAddressDeny=any`) | DROP |

- Anti-réentrance : si `IN_OPENCODE_CAGE` est déjà défini, la fonction
  refuse (`return 1`) — pas de cage dans une cage.
- Vérification : `scripts/verify-tor.sh` section 11 (check `IN_OPENCODE_CAGE=1`
  → WARN si hors cage, FAIL si `systemd-run` absent).

## Méthode ALTERNATIVE — nftables avec groupe DÉDIÉ (jamais le groupe user)

Si une isolation kernel reste souhaitée un jour :

1. **Créer un groupe DÉDIÉ** (par l'humain, sudo requis) — par exemple
   `opencode-cage` : `sudo groupadd opencode-cage`, puis y rattacher
   l'utilisateur agent.
2. Utiliser `meta skgid <gid-du-groupe-dédié>` en cible de drop.
   - ❌ **JAMAIS `meta skgid <gid du groupe user principal>`** : ce GID est
     partagé par tout le réseau de l'utilisateur, pas seulement l'agent —
     c'est dangereux.
3. Placeholders **toujours à résoudre manuellement** avant application
   (`<tor-bridge-ip>` via `docker network inspect redteam-tor-net`,
   `<gid-du-groupe-dédié>` via `id -g` — ou mieux, le gid du groupe
   `opencode-cage`).
4. **sudo interdit en agent** : l'application de la règle reste un geste
   humain, une fois, manuellement. Aucun script du repo ne fait `sudo`.

## Pourquoi l'abandon de nftables (raison P4)

- **Conflit iptables-nft CachyOS** : la stack iptables-nft de CachyOS rend
  l'application du ruleset `inet` non fiable / conflitante.
- **GID user partagé dangereux** : la règle `meta skgid <gid user>`
  aurait coupé **tout** le réseau de l'utilisateur, pas seulement l'agent.
- Méthode template nftables inapplicable en l'état (placeholders jamais
  substitués) et dangereuse → méthode kernel nft **abandonnée**,
  remplacée par la cage `systemd-run`.

## Résumé

| Élément | Statut |
|---|---|
| Cage `systemd-run --user --scope` | ✅ recommandée, opérationnelle (wrapper fish) |
| nftables kernel | ❌ abandonné (conflit iptables-nft CachyOS + GID user partagé) |
| Fallback `tor-wrap` fail-closed | ✅ toujours actif |
| `nftables-opsec.conf` / `nftables-apply.sh` | retirés volontairement |
