# Bulle VPN « pentest » — mode d'emploi

**But** : faire sortir **uniquement tes outils de pentest** par un VPN, sans jamais
toucher au réseau de ta machine. Ton navigateur normal, ton IDE, tes visios et tes
assistants IA restent sur la Freebox : **plus aucune déconnexion possible.**

---

## Utilisation

```fish
# un shell interactif DANS la bulle (tout ce que tu y fais sort par le VPN)
pentest-shell

# une commande ponctuelle dans la bulle
pentest-shell curl -s https://api.ipify.org
pentest-shell ffuf -u https://cible/FUZZ -w mots.txt
pentest-shell nmap -sV cible.tld
pentest-shell firefox        # navigateur complet dans la bulle
```

Si la bulle n'existe pas encore, `pentest-shell` la monte automatiquement.

```fish
sudo pentest-vpn status      # etat du tunnel + IP de sortie bulle vs PC
sudo pentest-vpn up          # monter / remonter
sudo pentest-vpn down        # detruire la bulle (le PC n'est jamais modifie)
```

---

## Comment ca marche

```
        wlan0 -> Freebox -> Internet          <-- ton PC : JAMAIS touche
          |
          +-- wgp (WireGuard -> Proton NL)    <-- le tunnel
                |
                +-- veth-h <=> veth-p  (10.200.200.0/24, NAT dans wgp)
                      |
                      +-- namespace "pentest" <-- tes outils
```

Deux mecanismes rendent l'ensemble non intrusif :

1. **Namespace reseau separe.** Seuls les processus lances via `pentest-shell`
   utilisent la bulle. La route par defaut de ta machine reste `wlan0`.
2. **Une seule regle de routage, ciblee** : `ip rule from 10.200.200.0/24 lookup 200`.
   Elle ne s'applique **que** aux paquets de la bulle. Ton trafic personnel
   (source `192.168.1.137`) n'est jamais concerne.

**Kill-switch naturel** : si le tunnel tombe, le NAT n'a plus de sortie -> la bulle
perd Internet et **ton PC continue de travailler**. Aucune fuite possible.

---

## Garanties verifiees le 2026-09-25

| Test | Resultat |
|---|---|
| IP de sortie dans la bulle | `89.39.107.194` (Naaldwijk, NL, AS49981 WorldStream = Proton) |
| IP de sortie du PC | `88.188.195.156` (Free) — inchangee |
| DNS dans la bulle | resolu par `10.2.0.1` **via le tunnel** (pas le DNS du PC) |
| DNS du PC | intact (`/etc/resolv.conf` -> stub `127.0.0.53`) |
| IPv6 dans la bulle | **bloque** (pas de fuite de ton IPv6 Free) |
| Route par defaut du PC | `wlan0`, jamais modifiee |
| Handshake WireGuard | OK, transport bidirectionnel |

Le DNS est le piege classique : le module NSS `resolve` parle au
`systemd-resolved` de la **machine** (donc hors du tunnel). Il est neutralise par
`/etc/netns/pentest/nsswitch.conf` (`hosts: files dns`).

---

## Limites du VPN gratuit

- Serveur gratuit unique ici : **NL-FREE#15** (Amsterdam). Tous les utilisateurs
  gratuits sortent par le meme pool d'IP -> une IP peut etre « grillee » par un
  site qui bloque les datacenters.
- Pas de port-forwarding, pas de choix du pays.
- **Pour du pentest autorise**, si une IP propre et stable est indispensable :
  Mullvad (5 €/mois, sans email, paiement anonyme) ou un VPS personnel
  (Hetzner/OVH) avec WireGuard — meme bulle, tu changes juste la config.

---

## Si le tunnel ne monte plus (serveur retire par Proton)

```fish
sudo pentest-vpn-refresh          # reconnecte Proton, reextrait la config, remonte la bulle
```

## Fichiers installes

| Chemin | Role |
|---|---|
| `/usr/local/sbin/pentest-vpn` | montage / demontage / etat de la bulle |
| `/usr/local/bin/pentest-shell` | entree dans la bulle (tes droits, pas root) |
| `/usr/local/sbin/pentest-vpn-refresh` | rafraichit la config WireGuard |
| `/etc/pentest-vpn/wg.conf` | cle privee + peer (droits 600, root) |
| `/etc/pentest-vpn/params.env` | adresse, DNS, MTU |
| `/etc/netns/pentest/` | resolv.conf + nsswitch.conf propres a la bulle |

## Tout retirer

```fish
sudo pentest-vpn down
sudo rm -f /usr/local/sbin/pentest-vpn /usr/local/sbin/pentest-vpn-refresh /usr/local/bin/pentest-shell
sudo rm -rf /etc/pentest-vpn /etc/netns/pentest
```

---

## Corrige au passage (sans rapport avec le VPN)

1. `/etc/resolv.conf` etait en mode **non-stub** : `glibc` lisait la liste brute des
   resolveurs et les interrogeait un par un (5 s de timeout chacun), ce qui faisait
   ramer **toute** la machine. Remis sur `stub-resolv.conf` : `getent` passe de
   **12,6 s a 5 ms**.
2. `anonymat.conf` impose `DNSOverTLS=yes` (strict). Or Windscribe bloque en DNS
   toute une liste d'adresses (dont les tiennes) : avec le mode strict, le systeme
   restait bloque 30-45 s sans pouvoir se rabattre -> **« ma connexion marche 30 s
   puis elle stoppe »**. Ajout de `/etc/systemd/resolved.conf.d/zz-vpn-compat.conf`
   (`DNSOverTLS=opportunistic`, `DNSSEC=allow-downgrade`).

---

# Integration au redteam-agent (`~/redteam-agent`)

Le framework exige une **preuve materielle** de tunnel (`rt_wg_manual_up` : iface
`wg[0-9]+` visible + handshake < 180 s) et refuse de tourner sinon
(`egress-wrap.sh` fail-closed). Comme la bulle contient un vrai `wg0`, **le contrat
est satisfait sans detour** :

```fish
redteam-bubble verify-vpn     # doit finir sur « egress pret pour cibles internet »
redteam-bubble start          # lance la stack DANS la bulle
redteam-bubble shell          # shell dans ~/redteam-agent, dans la bulle
redteam-bubble <cmd...>       # n'importe quelle commande du framework
```

Resultat mesure (2026-09-25) : `verify-vpn` **entièrement vert** dans la bulle,
`check_egress_contract.sh` -> **passed=15 failed=0**, et sur le PC (hors bulle)
`egress-wrap.sh` **refuse de tourner** -> le fail-closed fonctionne.

## 2 bugs corriges dans le depot (sauvegarde : `.backup-cline-20260925-201255/`)

**1. `scripts/lib/vpn_state.sh` — detection de handshake cassee.**
`wg show all latest-handshakes` sort `iface<TAB>pubkey<TAB>timestamp` (3 colonnes),
mais le code lisait `$2` = **la cle publique du peer**, evaluee a 0 en numerique.
Le test etait donc *toujours* faux : `rt_wg_manual_up` ne pouvait **jamais** renvoyer
true. Consequence : `verify-vpn` rouge en boucle et tous les outils bloques en
fail-closed. C'est la vraie raison pour laquelle le tunnel manuel decrit dans
`SETUP_WG.md` semblait « ne pas marcher ». Corrige en lisant `$3` (repli sur `$2`
pour rester compatible du format a 2 colonnes).

**2. `start-redteam.sh` — verdict d'egress conscient de la bulle.**
Les IP des serveurs **gratuits** sont annoncees sous l'AS du datacenter
(`AS49981 WorldStream B.V.`) et non « Proton » : le verdict « trafic EN CLAIR »
etait un **faux negatif**. Dans la bulle, l'isolation est structurelle, on compare
donc l'IP de sortie a l'IP directe de l'hote (`rt_bubble_host_ip`, relevee au
montage dans `/run/pentest-vpn/host-egress-ip`). Le kill-switch Windscribe est lui
aussi remplace par sa preuve structurelle (une seule route par defaut : `wg0`).

## Test complet realise le 2026-09-25 (cible autorisee : scanme.nmap.org / example.com)

| Axe | Test | Resultat |
|---|---|---|
| Contrat | `redteam-bubble verify-vpn` | ✅ tout vert (tunnel + egress ≠ IP hôte + IPv6 + kill-switch) |
| Contrat | `check_egress_contract.sh` **sur le PC** | ✅ `passed=15 failed=0` |
| Contrat | `check_egress_contract.sh` **dans la bulle** | ✅ `passed=13 failed=0 skipped=2` (les 2 fail-closed ne sont pas reproductibles avec un vrai tunnel present — sautés, plus de faux FAIL) |
| Egress | `egress-wrap.sh` / `tor-socks5-wrap.sh` / `tor-wrap.sh` | ✅ les 3 sortent en `89.39.107.194` (Proton) |
| Egress | process `node` lance par `egress-wrap` (= chemin MCP nmap) | ✅ Proton |
| DNS | `getent` + `dig @10.2.0.1` + `dig @1.1.1.1` | ✅ résolu via le tunnel |
| Fuites | IPv6 dans la bulle | ✅ `000` (aucune fuite) |
| Outil | `nmap -sT -Pn -p 22,80,443 scanme.nmap.org` | ✅ `22 open / 80 open / 443 open` |
| Outil | `nmap -sS` / `-sU` | ❌ « requires root » — nmap teste `geteuid()==0`, les `setcap` ne suffisent pas (voir plus bas) |
| Outil | `subfinder -d nmap.org` | ✅ `scannet.nmap.org, forum.nmap.org, wildcard-test.nmap.org` |
| Outil | `ffuf` | ✅ `Errors: 0` (ex. `example.com`) ; ❌ `scanme.nmap.org` = connexion réinitialisée **côté cible** |
| Outil | `katana -u ... -d 1` | ✅ crawl OK |
| Outil | `httpx` | ⚠️ **mauvais binaire** : `/usr/bin/httpx` = Python httpx, pas ProjectDiscovery (absent) |
| Outil | `nuclei` | ✅ `Templates loaded: 4245`, scan effectif, finding remonté (`dns-waf-detect`) — le WARNING `sonic/ast` n'est qu'un repli de perf |
| MCP | `test_mcp_handshake.sh` (12 serveurs) | ✅ **11/12 OK** — 410 outils exposés. `metasploit` = service RPC absent (`127.0.0.1:55553 refused`), rien à voir avec la bulle |
| Kill-switch | coupure de `wg0` en plein vol | ✅ bulle `7 OK / 5 KO` (KO = fenêtre de coupure), **PC `12 OK / 0 KO`** |
| Résilience | rebond `wg0 down` puis `pentest-shell` | ✅ auto-réparation (`default dev wg0` restauré, IP Proton) |
| PC | route par défaut / IP / DNS | ✅ `wlan0` / `88.188.195.156` / stub — jamais modifiés |

### Limites constatees

1. **`nmap` exige `geteuid()==0`** : ni `setcap`, ni les namespaces ne suffisent
   pour `-sS` / `-sU` / `-O`. Options : `-sT` (fonctionne, et passe mieux qu'un
   SYN à travers le NAT du tunnel) ou `sudo nmap` depuis la bulle, ou
   `chmod u+s /usr/bin/nmap` (Kali historique — décision de sécurité à toi).
2. **`httpx` de ProjectDiscovery absent** : `pacman`/`go install` le manquant,
   sinon le framework invoque Python httpx.
3. **Metasploit** : `msfrpcd` non démarré (et `msfconsole` hors PATH) →
   `scripts/start_metasploit_mcp.sh` à lancer avant le probe.
4. **Docker** : les conteneurs restent hors bulle → `REDTEAM_RUNTIME_MODE=local`.

Les conteneurs sont crees par le daemon, qui vit dans le namespace de l'hote ->
**ils ne suivent pas la bulle**. `redteam-bubble` pose donc automatiquement
`REDTEAM_RUNTIME_MODE=local`, qui utilise les binaires installes localement
(`katana`, `nuclei`, `httpx`, `subfinder`, `nmap`, `ffuf`). Pour du tout-Docker,
il faudrait un daemon Docker par namespace (rootless + `unshare`), c'est un autre
chantier.

## Ajouts a la bulle (v2)

- `wg0` vit **dans** le namespace (v1 le mettait sur l'hote + regle `ip rule`).
  L'hote ne porte plus aucune iface VPN ni regle de routage : il ne reste qu'un
  veth et du NAT pour le seul trafic de l'endpoint.
- Le binaire `wg` est inaccessible a un utilisateur non-root dans un namespace
  cree par root. D'ou un shim `/usr/local/lib/pentest-shims/wg` (-> `sudo -n wg`),
  place en tete du `PATH` uniquement **dans** la bulle, pour que la detection du
  framework fonctionne avec tes droits.
- `up` amorce le tunnel (ping vers le DNS du tunnel) pour qu'un handshake existe
  des la fin du montage.
