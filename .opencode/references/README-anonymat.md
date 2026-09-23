# Anonymat 2 niveaux — mise en œuvre (2026-09-23, cage v4)

## Fichiers livrés (dans ce dossier `references/`)

| Fichier | Rôle | Installation |
|---|---|---|
| `opencode-caged.fish` | Cage **v4 fail-CLOSED** (VPN requis, **denylist lab uniquement**, tout le web/CTF/LLM autorisé, appel root via helper) | copie vers `~/.config/fish/functions/` = **geste humain** |
| `opencode-cage-root` | Helper root bash (reçoit **denylist** + commande, lance `systemd-run --scope` avec CAP_BPF) | `sudo cp` vers `/usr/local/bin/opencode-cage-root` = **geste humain** |
| `sudoers-opencode-cage` | Entrée sudoers `NOPASSWD` limitée au helper | `sudo cp` vers `/etc/sudoers.d/opencode-cage` = **geste humain** |
| `resolved-anonymat.conf` | Drop-in DoT (Cloudflare + DNSSEC) | `sudo install` dans `/etc/systemd/resolved.conf.d/` = **geste humain** |
| `proxychains-anonymat.conf` | ProxyChains `dynamic_chain`, `proxy_dns`, 5000 ms | invoqué via `-f`, aucun sudo |
| `px.fish` | Fonction de confort `px <cmd>` | copie vers `~/.config/fish/functions/` = **geste humain** |

## ✅ Cage v4 : FAIL-CLOSED, denylist lab uniquement (implémenté)

**Problème v3** : la cage filtrait en `Deny=any + Allow=lab` → bloquait TOUT sauf le lab → tuait l'agent (LLM cloud, web, CTF = bloqués).

**Solution v4** : la cage filtre en `Allow=any + Deny=lab` → **autorise tout le web/CTF/LLM** tout en **bloquant les cibles LAB** (127/8, 192.168.56.0/24, 10.0.0.0/8, 172.21.0.0/16).

- La cage **protège le LAB contre l'agent** (l'agent ne peut pas attaquer le lab interne) — pas l'inverse.
- Si le helper/sudoers est absent → wrapper échoue (`return 1`) = fail-closed.
- Si VPN absent → wrapper échoue (`return 1`) = fail-closed.
- Dans la cage active (VPN up + helper installé) : `curl https://google.com` / `curl https://un-site-ctf.com` → **PASSENT** ✅ (tout le web est autorisé). `curl https://192.168.56.x` → **ÉCHOUE** ✅ (lab bloqué).

### Flow humain d'installation (sudo interdit en agent — P4)

```fish
sudo cp ~/redteam-agent/.opencode/references/opencode-cage-root /usr/local/bin/opencode-cage-root
sudo chmod +x /usr/local/bin/opencode-cage-root
sudo cp ~/redteam-agent/.opencode/references/sudoers-opencode-cage /etc/sudoers.d/opencode-cage
```
Puis vérifier : `sudo -n true` → OK. Après : `opencode-caged` lance `sudo /usr/local/bin/opencode-cage-root $denylist -- opencode` → cage EFFICACE.

### Exécution

```fish
opencode-caged  # lance opencode dans la cage (VPN requis, fail-closed)
```
Le wrapper construit `denylist = 127.0.0.0/8 192.168.56.0/24 10.0.0.0/8 172.21.0.0/16` et appelle le helper.

## Gestes humains (« sudo interdit en agent » — P4)

### 1. Windscribe Free (déjà installé : `/usr/local/bin/windscribe`) — VPN gratuit retenu (10-15 Go/mois, durée illimitée)
```fish
windscribe login            # compte gratuit (email = 10 Go, tweet = 15 Go)
windscribe connect          # serveur le plus rapide (ou -c <pays>)
curl -s https://am.i.mullvad.net/ip   # hors cage → doit afficher une IP VPN ≠ IP réelle
```
Fail-closed : `opencode-caged` **refuse de démarrer** (return 1) tant qu'aucune iface `proton*|wg*|tun*|mullvad*|wind*|vpn*|wireguard*` n'a d'adresse **OU** que le helper root/sudoers est absent.

**Tor** : nœuds de sortie bloqués par les WAF (Cloudflare, etc.) → inutilisable pour le lab CTF. `tor-wrap` (fallback repo) = Tor-seul, hors scope lab.

### 2. Drop-in DoT (le DoT est déjà actif via Quad9 auth TLS ; ce drop-in épingle Cloudflare)
```fish
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo install -m644 ~/redteam-agent/.opencode/references/resolved-anonymat.conf /etc/systemd/resolved.conf.d/anonymat.conf
sudo systemctl restart systemd-resolved
resolvectl status           # vérifier : +DNSOverTLS, DNSSEC=yes/supported
```
Caveats : (a) les DNS **par lien** NM (hotspot `iPhone` sur `wlan0`) persistaient — `ipv4.ignore-auto-dns yes` ne suffit pas (ne touche que le DHCP) car `ipv4.dns` était **statique** (`9.9.9.9,149.112.112.112`) ; le vrai fix : `sudo nmcli con modify <profil> ipv4.dns "" ipv6.dns ""` + `sudo nmcli device reapply wlan0`. Juger sur `resolvectl dns` (vide = bon), pas `nmcli device show` ; (b) quand Windscribe est actif, il prend le contrôle du DNS (R.O.B.E.R.T.) → le DoT vers Cloudflare est **surchargé** (DNS → Windscribe, chiffré mais eux voient les domaines). Pas de fuite, mais modèle de confiance décalé.

### 3. ProxyChains
`proxychains-anonymat.conf` a besoin d'un proxy SOCKS5 **renseigné** dans `[ProxyList]` (Proton n'expose pas de SOCKS en CLI ; liste vide = `no valid proxy found`). Usage : `px <commande>` uniquement — jamais en wrapper global (−30 à −50 %).

**Quota Windscribe** : 10-15 Go/mois — largement suffisant ici car la cage garde le lab en local ; le VPN ne porte que les `curl` de vérification + l'API de l'agent (quelques centaines de Mo par session). Usage mesuré : 0/10 Go après connect/déco.

## Étape 4 — vérification finale
- **Hors cage** (VPN up) : `curl -s https://am.i.mullvad.net/ip` → IP VPN ≠ IP réelle ✅
- **Dans cage (v4)** : `curl https://google.com` / site CTF → **PASSENT** ✅ (tout le web autorisé) ; `curl https://192.168.56.x` / lab interne → **ÉCHOUE** ✅ (lab bloqué)
- **Dans cage, état actuel (v4 root)** : web accessible ✅ + lab bloqué ✅

## Interdits (rappel)
Pas de ProxyChains partout ; pas de chaîne VPN+Tor sauf niveau APT (inutile pour le lab CTF — le `--tor` de protonvpn est donc proscrit, les exits Tor sont bloqués par les WAF) ; ne pas toucher la config `systemd-resolved` globale sans test (ici : DoT déjà actif et vérifié avant le drop-in).

**Attention** : le denylist 127/8 bloque aussi le localhost → si le LLM est local (hermes sur 127.x.x.x), il sera coupé dans la cage. Si le LLM est un tunnel distant (hermes-tunnel), pas d'impact.

## Impact vitesse (plan)
WireGuard −7 à −15 % (anonymat critique) · DoT ~0 % (critique) · cage ~0 % (important) · ProxyChains −30 à −50 % (bonus).

## Side-notes
- Services user en crashloop : `hermes-tunnel.service`, `lightrag.service`, `bookmark-watcher.service` (non touchés)
- Journal resolved : `DNSSEC validation failed … relay.openchamber.dev failed-auxiliary`
- Repo : `windscribe` installé en `/usr/local/bin/windscribe` (découverte initiale)
- Shell : fish, fonction `px` dans `~/.config/fish/functions/`
- **Logique cage** : Denylist lab uniquement (v4) — l'agent est opérationnel (web/CTF/LLM) à l'intérieur de la cage. La cage protège le LAB, pas l'agent.
