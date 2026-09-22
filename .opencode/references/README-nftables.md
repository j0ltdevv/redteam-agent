# P4 nftables — kernel-level OPSEC (application manuelle)

> Statut honnête : **P4 = 40% applicatif + config prête, application kernel manuelle.**
> nftables/bwrap exigent sudo (interdit en agent). Tout est versionné ici,
> application unique par l'humain. En attendant, le fallback applicatif
> reste actif.

## Fallback applicatif déjà en place

- `tor-wrap` fail-closed : exit 1 si pas de proxy, refuse sans proxy.
- Aucun trafic direct sans Tor au niveau applicatif.

## Procédure d'application pas-à-pas (humain, sudo)

1. Résoudre les placeholders dans `.opencode/references/nftables-opsec.conf` :
   - `<tor-bridge-ip>` → IP du bridge `redteam-tor-net` :
     `docker network inspect redteam-tor-net`
   - `<opencode-gid>` → gid de l'user opencode :
     `id -g`
2. Copier la conf :
   `sudo cp .opencode/references/nftables-opsec.conf /etc/nftables.d/opencode-opsec.conf`
3. Appliquer via le script versionné :
   `sudo bash .opencode/references/nftables-apply.sh`
   (ou direct : `sudo nft -f /etc/nftables.d/opencode-opsec.conf`)
4. Vérifier :
   `sudo nft list ruleset | grep opencode`
   Attendu : table `inet opencode` + chain `output` visibles.
5. Log : `/var/log/opencode-nftables.log`

## Check à ajouter plus tard (hors scope agent — ne pas modifier les scripts)

Quand P4 kernel sera appliqué, ajouter dans `scripts/verify-tor.sh`
 best minimal check :

```bash
if sudo nft list ruleset | grep -q opencode
then
    echo "OK nftables opencode ruleset actif"
else
    echo "WARN fallback applicatif actif (kernel P4 non applique)" >&2
fi
```

- `grep -q opencode` → OK (exit 0) : ruleset kernel actif.
- Sinon WARN : fallback applicatif actif, P4 kernel restant à appliquer.
- Ne pas faire échouer le verify sur WARN tant que l'application kernel
  reste manuelle.
