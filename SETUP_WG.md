# Egress WireGuard manuel — contourner le daemon Windscribe buggé

## Pourquoi

Le daemon `windscribe-cli` 2.21.7 (AUR) établit la négociation à moitié (DNS
injecté, état « Connecté » affiché) mais **ne crée jamais d'interface tunnel
côté kernel** — bug confirmé par logs + absence d'iface + IP de sortie en clair.
La mise à jour 2.24.12 est bloquée par le conflit AUR/pacman.

Solution : **tunnel WireGuard natif via `wg-quick`**, avec ton abonnement
Windscribe existant. Le daemon buggé n'est plus utilisé du tout ; le tunnel
kernel `wg0` est détecté par `scripts/lib/vpn_state.sh` (nouveau chemin
`rt_wg_manual_up`) et fait passer `./start-redteam.sh verify-vpn` au vert.

## Étape 1 — Télécharger ton profil WireGuard (toi, 3 min)

1. Va sur https://windscribe.com et connecte-toi à ton compte.
2. Menu **Setup** → **WireGuard** (ou https://windscribe.com/getwireguard).
3. Choisir un serveur proche (ex. Paris) → **Download Config**.
   Tu obtiens un fichier `wg-xxx.conf` contenant `[Interface]` + `[Peer]`.
4. Dépose-le où tu veux, ex. `~/Téléchargements/wg-paris.conf`.

⚠️ Le fichier contient ta clé privée : ne le partage pas, ne le commit pas.

## Étape 2 — Installer le profil (root, 1 min)

```bash
sudo bash scripts/setup-wg.sh install ~/Téléchargements/wg-paris.conf redteam
```

Le script valide le profil, l'installe en `/etc/wireguard/redteam.conf`
(perms 600) et ajoute le DNS Windscribe si absent.

## Étape 3 — Monter le tunnel + kill-switch (root, 30 s)

```bash
sudo bash scripts/setup-wg.sh up redteam
```

Cela fait :
- `wg-quick up redteam` → interface kernel `wg0` réelle ;
- kill-switch nftables : **tout** le trafic sortant est droppé sauf
  endpoint WG, loopback, LAN et interface `wg0` (aucune fuite possible).

## Étape 4 — Vérifier (sans root)

```bash
./start-redteam.sh verify-vpn
```

Attendu, tout vert :
- `tunnel WireGuard manuel actif (wg-quick, handshake récent)`
- `sortie IPv4 appartient à Windscribe`
- `pas de fuite IPv6` (le kill-switch drope aussi l'IPv6 sortant)

## Au quotidien

```bash
sudo bash scripts/setup-wg.sh up redteam      # monter (avant /engage internet)
sudo bash scripts/setup-wg.sh status redteam  # état + IP de sortie
sudo bash scripts/setup-wg.sh down redteam    # démonter
```

Le daemon `windscribe-cli` peut rester tel quel : il ne sert plus qu'au
diagnostic (`rt_cli_tunnel_connected` ignore son état si un tunnel wg manuel
est actif).

## Notes techniques

- Détection dans `vpn_state.sh` : iface `wg0..9` présente ET handshake peer
  de moins de 3 minutes (`wg show all latest-handshakes`) — un tunnel monté
  mais sans handshake (endpoint joignable mais clé expirée) est refusé.
- Le kill-switch nftables (table `redteam-killswitch`) est armé/désarmé par
  `setup-wg.sh up|down`. Il survit à un crash de `wg-quick` : tant qu'il est
  armé, rien ne sort hors du tunnel.
- `verify-vpn` continue de vérifier l'org de l'IP de sortie = Windscribe : un
  profil d'un autre provider passera le tunnel mais échouera au check org
  (comportement voulu, change la regex si tu changes de provider).
- L'ancien chemin Windscribe (CLI + iface) reste supporté et prioritaire en
  diagnostic si les deux coexistent.

---

# Variante ProtonVPN (compte free)

Le Config Generator Windscribe nécessite un compte Pro. Alternative gratuite :
ProtonVPN free (serveurs NL/US/JP), config WireGuard téléchargeable même en free.

## Étapes

1. Crée un compte sur https://account.protonvpn.com/signup (plan Free).
2. Connecte-toi sur https://account.protonvpn.com/downloads → **WireGuard
   configuration** → Linux → choisir un serveur free (ex. Netherlands) →
   générer le `.conf`.
3. Puis exactement le même setup que Windscribe (étapes 2-4 ci-dessus) :

```
sudo bash scripts/setup-wg.sh install ~/Téléchargements/NL-xxx.conf redteam
sudo bash scripts/setup-wg.sh up redteam
./start-redteam.sh verify-vpn
```

Le check org accepte désormais `Proton AG` en plus de `Windscribe` (les deux
sont des sorties VPN légitimes).

⚠️ Free = 1 appareil connecté à la fois, 3 pays, débit variable. Suffisant
pour de l'OSINT et un premier engagement web de test.
