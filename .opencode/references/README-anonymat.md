# Anonymat 2 niveaux — mise en œuvre (2026-09-23)

## Fichiers livrés (dans ce dossier `references/`)

| Fichier | Rôle | Installation |
|---|---|---|
| `opencode-caged.fish` | Cage fail-closed (VPN requis, allowlist dynamique) | copie vers `~/.config/fish/functions/` = **geste humain** (le repo ne touche jamais `~/.config/`) |
| `resolved-anonymat.conf` | Drop-in DoT (Cloudflare + DNSSEC) | `sudo install` dans `/etc/systemd/resolved.conf.d/` = **geste humain** |
| `proxychains-anonymat.conf` | ProxyChains `dynamic_chain`, `proxy_dns`, 5000 ms | invoqué via `-f`, aucun sudo |
| `px.fish` | Fonction de confort `px <cmd>` | copie vers `~/.config/fish/functions/` = **geste humain** |

## ⚠️ Constat critique : la cage `--user` est fail-open aujourd'hui (prouvé)

- Journal : `run-….scope: unit configures an IP firewall, but not running as root.`
- Le manager `systemd --user` n'a ni `CAP_BPF` ni `CAP_PERFMON` (CapEff = `CAP_WAKE_ALARM` seul) → les programmes BPF d'`IPAddress*` ne sont **jamais attachés**.
- Test empirique : scope avec `IPAddressDeny=any` + allow `127.0.0.0/8` uniquement → `curl https://1.1.1.1` = **301 (passe)**, `curl https://google.com` = **301 (passe)**.
- Conséquence : **l'étape 4 du plan (« google doit échouer dans la cage ») échoue en l'état.** Le wrapper affiche maintenant un `[opsec] WARN` à chaque lancement tant que le filtre est inerte.

## Gestes humains (« sudo interdit en agent » — P4)

### 1. ProtonVPN (déjà installé : CLI officiel v1.0.3, `/usr/bin/protonvpn`)
```fish
protonvpn signin            # 1ʳᵉ fois seulement
protonvpn connect           # serveur le plus rapide (PAS de --tor : interdit)
curl -s https://am.i.mullvad.net/ip   # hors cage → doit afficher l'IP Proton
```
Fail-closed : `opencode-caged` **refuse de démarrer** (return 1) tant qu'aucune iface `proton*|wg*|tun*|mullvad*` n'a d'adresse.

### 2. Drop-in DoT (le DoT est déjà actif via Quad9 auth TLS ; ce drop-in épingle Cloudflare)
```fish
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo install -m644 ~/redteam-agent/.opencode/references/resolved-anonymat.conf /etc/systemd/resolved.conf.d/anonymat.conf
sudo systemctl restart systemd-resolved
resolvectl status           # vérifier : +DNSOverTLS, DNSSEC=yes/supported
```
Caveats : (a) les DNS **par lien** NM (hotspot `iPhone` sur `wlan0`) persistent — si besoin : `nmcli con modify iPhone ipv4.ignore-auto-dns yes ipv4.dns 1.1.1.1` ; (b) certains outils dépendent du DNS local — ici pas de régression, le DoT était déjà global.

### 3. Rendre la cage réelle (au choix, à arbitrer)
```fish
# a) Préuve que le filtre fonctionne en racine (doit ÉCHEOUER) :
sudo systemd-run --scope -p IPAddressDeny=any -p IPAddressAllow=127.0.0.0/8 curl -s -m 5 https://1.1.1.1
```
- **b)** helper root-owned (`/usr/local/bin/…`) + entrée sudoers `NOPASSWD` strictement limitée → wrapper appelle `sudo -n` (surface d'escalade à peser) ;
- **c)** revisiter nftables (abandonné pour conflit `iptables-nft` sur CachyOS — arbitrage à refaire).

### 4. ProxyChains
`proxychains-anonymat.conf` a besoin d'un proxy SOCKS5 **renseigné** dans `[ProxyList]` (Proton n'expose pas de SOCKS en CLI ; liste vide = `no valid proxy found`). Usage : `px <commande>` uniquement — jamais en wrapper global (−30 à −50 %).

## Étape 4 — vérification finale
- **Hors cage** (VPN up) : `curl -s https://am.i.mullvad.net/ip` → IP Proton ✅
- **Dans cage, filtre racine actif** : `curl -s https://am.i.mullvad.net/ip` → IP Proton ✅ (l'IP résolue de `am.i.mullvad.net` est ajoutée dynamiquement à l'allowlist) ; `curl -s https://google.com` → échec ✅
- **Dans cage, état actuel (`--user`)** : google **peut passer** (fail-open prouvé) ❌

## Interdits (rappel)
Pas de ProxyChains partout ; pas de chaîne VPN+Tor sauf niveau APT (inutile pour le lab CTF — le `--tor` de protonvpn est donc proscrit) ; ne pas toucher la config `systemd-resolved` globale sans test (ici : DoT déjà actif et vérifié avant le drop-in).

## Impact vitesse (plan)
WireGuard −7 à −15 % (anonymat critique) · DoT ~0 % (critique) · cage ~0 % (important) · ProxyChains −30 à −50 % (bonus).
