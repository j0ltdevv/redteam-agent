# ATT&CK MAP — table de correspondance minimale (T06)

Chaque étape d'exploitation est taguée `[ATT&CK: Txxxx]` dans le log/findings.

| Phase / action | Tactic | Technique exemple |
|---|---|---|
| Recon passive (DNS, OSINT, certs) | TA0043 Reconnaissance | T1595 Active Scanning |
| Recon active (nmap, dirbust) | TA0043 Reconnaissance | T1595.001 Scan IP Blocks |
| Enumeration sous-domaines | TA0043 Reconnaissance | T1596.001 DNS |
| Fingerprinting web (whatweb) | TA0043 Reconnaissance | T1592 Gather Victim Host Info |
| Weaponisation payload | TA0001 Initial Access | T1566 Phishing (lab) |
| Exploitation service web | TA0002 Execution | T1190 Exploit Public-Facing App |
| Exécution commande (RCE) | TA0002 Execution | T1059 Command Interpreter |
| Élévation de privilèges | TA0004 Privilege Escalation | T1068 |
| Contournement défense (WAF/AV) | TA0005 Defense Evasion | T1027 Obfuscated Files |
| Persistence (webshell) | TA0003 Persistence | T1505.003 Web Shell |
| Escalade credentials (dump) | TA0006 Credential Access | T1003 OS Credential Dumping |
| Mouvement latéral | TA0008 Lateral Movement | T1021 Remote Services |
| Exfiltration / impact | TA0010/TA0040 | T1041 Exfil Over C2 |
| Collection données cible | TA0009 Collection | T1005 Data from Local System |
| Command & control (interactsh OOB) | TA0011 Command and Control | T1105 Ingress Tool Transfer |
| Discovery réseau interne | TA0007 Discovery | T1046 Network Service Discovery |
