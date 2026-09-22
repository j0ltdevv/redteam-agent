# MEMORY_DAG — mémoire cible-centré (T04)

Format strict — un nœud par bloc `## NODE <id>` :

```
## NODE <id>
- type: observation | hypothesis | action | finding
- target: <host:port>
- content: <une ligne>
- confidence: 0-100
- depends_on: [<ids>]
- falsifier: <condition qui tue ce nœud>
```

Règles (implémentées dans copilot.txt) :
1. Début de tour : relire ce fichier.
2. Après chaque action : ajouter/mettre à jour un nœud.
3. Avant toute conclusion : nœud `finding` = falsifier non déclenché + confidence ≥ seuil gate (T05).

---

## NODE obs-001
- type: observation
- target: lab-mock:80
- content: exemple — banner HTTP server=nginx/1.24 sur port 80
- confidence: 100
- depends_on: []
- falsifier: requête retournant un autre header Server

## NODE hyp-001
- type: hypothesis
- target: lab-mock:80
- content: exemple — path /admin exposé sans auth
- confidence: 40
- depends_on: [obs-001]
- falsifier: GET /admin renvoie 302/401 avec preuve d'auth
