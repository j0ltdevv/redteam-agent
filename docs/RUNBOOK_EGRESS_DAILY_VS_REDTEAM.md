# Runbook — Daily vs RedTeam : séparation réseau & VPN on-demand

**Date :** 2026-09-27 — post `netfix-20260927-112525` + `windscribe-off`
**But :** daily sans Windscribe/DNS blackout, redteam VPN/bulle uniquement à la demande.

## 1. État validé (mesure, pas promesse)

| Signal | Valeur |
|---|---|
| Résolution | `9/9` endpoints <0.5s (api.ipify.org … raw.githubusercontent.com) |
| Resolvers globaux | `9.9.9.9#dns.quad9.net 149.112.112.112 2620:fe::fe 2620:fe::9 + 1.1.1.1#cloudflare-dns.com 2606:4700:4700::1111` + fallback `8.8.8.8 2001:4860:4860::8888` (`99-pentest-dns.conf` = source unique) |
| Lien wlan0 | `192.168.1.254 fd0f:ee:b0::1` (box, `ignore-auto-dns=no`) |
| DoT / DNSSEC | `DNSOverTLS=opportunistic` / `DNSSEC=allow-downgrade` (`zz-vpn-compat.conf`) — strict neutralisé |
| MAC | `stable` + `${CONNECTION}` (NM 1.58 : seul `[connection]` effectif), `wifi.scan-rand-mac-address=yes` (scans seuls). Mesuré `8A:6E:9C:12:F3:83 / permaddr B8:1E:A4:E6:54:29` |
| Box | `192.168.1.76/24 via 192.168.1.254` bail 12h, ping 3.2ms |
| Windscribe daily | `helper inactive (disabled)`, `nft table inet windscribe` absente, autostart `.disabled`, `app-windscribe@autostart.service` masked |
| `vpn-up.sh --check` | `NON connecté — 88.188.195.156` exit 1 (read-only, correct en daily) |
| `vpn-up.sh --diagnose` | `DNS ok / route 1.1.1.1 via 192.168.1.254 dev wlan0 / IP 88.188.195.156` exit 0 |
| `check_egress_contract.sh` | `passed=14 failed=1 warn=1` — FAIL = faux positif `opencode.json` (vrai `opencode.jsonc`) |

Backups : `~/backups/netfix-20260927-112525/` (13 fichiers) + `~/backups/windscribe-off/`.

## 2. Mode DAILY (défaut, stable, sans VPN)

C'est le mode bureautique / OpenCode PID 7850/7853 / `lid-keep-awake`.

```bash
# Vérifier daily propre (read-only, ~3s)
./scripts/vpn-up.sh --check
./scripts/vpn-up.sh --diagnose
resolvectl status | grep -E 'DNS Servers|Current DNS|DNSOverTLS'
sudo nft list tables | grep -q windscribe && echo KO || echo OK  # attendu OK (= absent)
systemctl is-active windscribe-helper.service   # attendu inactive
getent hosts api.ipify.org && getent hosts github.com && echo DNS_OK
```

Si helper relancé (update Windscribe, autostart recréé) :

```bash
./scripts/vpn-up.sh --down
systemctl --user mask app-windscribe@autostart.service 2>/dev/null || true
mv ~/.config/autostart/windscribe.desktop{,.disabled} 2>/dev/null || true
```

**Ne jamais faire en daily :** `windscribe-cli connect`, `pentest-vpn up` sur hôte, `systemctl enable/start windscribe-helper`, `DNSOverTLS=strict`.

## 3. Mode REDTEAM — deux variantes, on-demand seulement

### 3A. Windscribe hôte (stealth TLS 443, hotspot-safe)

```bash
./scripts/vpn-up.sh                # = stealth (défaut, wstunnel TLS 443, survit CGNAT)
./scripts/vpn-up.sh tcp:443        # OpenVPN TCP (plus rapide sur Wi-Fi stable)
./scripts/vpn-up.sh wireguard      # uniquement Wi-Fi fixe
./scripts/vpn-up.sh --check        # attendu exit 0 : connecté + IP != 88.188.x
./scripts/opsec-check.sh           # verdict tunnel/bulle attendu (5-12s)
./scripts/check_egress_contract.sh # gate fail-closed
./scripts/vpn-up.sh --down         # RESTAURE le daily : disconnect + stop helper + nft retiré
```

Lifecycle : `ensure_helper()` (10s wait), `stop_helper()` (retire pare-feu), `down()` (disconnect+stop), `fetch_egress_ip()` double sonde (`api.ipify.org` → `1.1.1.1/cdn-cgi/trace` sans DNS), `firewall_state()`, `diagnose()`, fail-closed exit 2 si tunnel sans IP vérifiée, `stop_helper` auto sur échec 45s.

### 3B. Bulle netns `pentest` — recommandé, zéro impact hôte

```bash
sudo pentest-vpn up                # crée netns pentest, wg0 DANS le netns, veth 10.200.200.1↔.2
sudo pentest-vpn status            # IP bulle 89.39.x Proton NL vs hôte 88.188.x Free inchangé
pentest-shell                      # shell interactif dans la bulle (tout sort par wg0)
pentest-shell curl -4 https://api.ipify.org
redteam-bubble verify-vpn          # opsec-check dans la bulle (verdict bulle)
redteam-bubble start               # lance la stack (REDTEAM_RUNTIME_MODE=local)
sudo pentest-vpn down              # détruit la bulle, hôte jamais modifié
```

Garanties mesurées 2026-09-25 : IP bulle `89.39.107.194 AS49981 Proton`, DNS bulle `10.2.0.1 via wg0`, DNS hôte `127.0.0.53` intact, IPv6 bloqué dans bulle, route hôte `wlan0` jamais touchée, kill-switch structurel (pas de default hors wg0 → bulle morte si tunnel tombe, PC OK). Auto-réparation : `pentest-shell` restaure `default dev wg0` si noyau a flush les routes.

Docker reste hors bulle (daemon vit dans ns hôte) → `REDTEAM_RUNTIME_MODE=local` (binaires `katana/nuclei/httpx/nmap`).

## 4. Pièges connus

- **NM 1.58** ignore `[device] cloned-mac-address` — seul `[connection]` compte.
- **`random` MAC** = 145 MACs/90min → baux DHCP épuisés → plus de bail IPv4 → DNS IPv4-only KO (SLAAC IPv6 continue). `stable+${CONNECTION}` corrige.
- **Helper sans tunnel** = `nft inet windscribe` DROP `53 → 1.1.1.1/9.9.9.9/149.112.112.112/192.168.1.254` → blackout daily. `masked` + `--down` évite.
- **`windscribe-cli status` ment** : 2 lignes `État de connexion`, 1re = daemon. `vpn_state.sh` lit la dernière + exige preuve matérielle `tun/utun/wg/ppp/xfrm` (sauf `RT_VPN_TRUST_CLI=1`).
- **DoT** : systemd-resolved cumule tous les `DNS=` des drop-ins, dernière politique gagne en silence. `99-pentest-dns.conf` seule source résolveurs.
- **`wg show` `$2 = pubkey, $3 = timestamp`** — ancien `rt_wg_manual_up` lisait `$2` → toujours faux, corrigé.
- **`opsec_guard` vs `vpn_state`** : `vpn_state` = tunnel monté ?, `opsec_guard` = par où sort réellement le trafic ? (direct_ip vs exit_ip). Wrappers refusent sur `CLAIR/INCONNU`.

## 5. Restauration

```bash
sudo cp ~/backups/netfix-20260927-112525/nm-conf.d/99-anon.conf /etc/NetworkManager/conf.d/
sudo cp ~/backups/netfix-20260927-112525/resolved.conf.d/* /etc/systemd/resolved.conf.d/
sudo nmcli general reload && sudo systemctl restart systemd-resolved
systemctl --user mask app-windscribe@autostart.service
sudo systemctl enable --now windscribe-helper.service  # si besoin redteam hôte
```

Voir `bubble/README.md` pour `pentest-vpn-refresh` (serveur Proton free retiré).
