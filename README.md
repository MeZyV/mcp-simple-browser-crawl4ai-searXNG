# MCP Search & Browse (SearXNG + Crawl4AI)

Serveur MCP (Model Context Protocol) qui permet à un client LLM de :

- rechercher sur le web (via SearXNG)
- ouvrir une page et récupérer un contenu propre (via Crawl4AI, en markdown)

Ce dossier est prévu pour une exécution "docker only".

## Architecture

```
Client LLM (Claude / agent / etc.)
        |
        | MCP (SSE)
        v
mcp-browser (FastMCP)  :8003
  - tool: search
  - tool: open
  - tool: find
        |
        | recherche -> searxng (interne)
        | fetch     -> crawl4ai (interne)
        v
SearXNG + Crawl4AI + Redis

Optionnel (secondaire / fallback):
mcpo (proxy MCP) :8004 -> http://mcp-browser:8003/sse
```

## Services Docker

Définis dans `docker-compose.yml` :

- `mcp-browser` : serveur MCP (expose `8003:8003`)
- `searxng` : métamoteur de recherche (port non publié par défaut)
- `crawl4ai` : service de scraping headless Chromium (port non publié par défaut)
- `redis` : cache / dépendance Crawl4AI
- `mcpo` : proxy MCP (expose `8004:8004`) — **service secondaire / fallback**

Remarque : SearXNG et Crawl4AI sont accessibles uniquement sur le réseau Docker `search-net` (sauf si vous publiez leurs ports).

## Prérequis

- Docker + Docker Compose

## Démarrage rapide (Docker)

Depuis ce dossier :

```bash
docker compose up -d --build
```

Pour arrêter :

```bash
docker compose down
```

## Configuration (.env)

1) Copiez le template :

```bash
cp .env.example .env
```

2) Éditez `.env` (minimum : secret SearXNG).

Variables typiques utilisées par la stack :

- `SEARXNG_SECRET` : requis par SearXNG
- `SEARXNG_URL_EXT` : URL interne utilisée par `mcp-browser` (par défaut `http://searxng:8080`)
- `CRAWL4AI_URL_EXT` : URL interne utilisée par `mcp-browser` (par défaut `http://crawl4ai:8002`)
- `CRAWL4AI_API_TOKEN` : optionnel (si vous protégez Crawl4AI)
- `MCP_BROWSER_PORT` : port du serveur MCP (défaut `8003`)
- `PROXY_URL` : optionnel (proxy pour Chromium côté Crawl4AI)

## Endpoints

### Endpoint principal (recommandé)

- MCP SSE : `http://localhost:8003/sse`

### Endpoint secondaire / fallback (mcpo)

- Proxy MCP : `http://localhost:8004`

`mcpo` lance un proxy vers `http://mcp-browser:8003/sse`. Utile si vous préférez interposer un wrapper/proxy (par ex. pour certains environnements).

## Tools MCP exposés

Le serveur `mcp-browser` expose :

- `search(query, topn=10, source=None)` : recherche via l’API JSON de SearXNG
- `open(id, cursor, loc, num_lines, view_source=False, source=None)` : ouvre une URL ou un résultat et renvoie un contenu lisible (markdown en priorité)
- `find(pattern, cursor=-1)` : recherche exacte d’un motif dans la page courante

## Dépannage (ports non exposés)

Par défaut, `searxng` et `crawl4ai` ne publient pas leurs ports sur `localhost`.

- Pour accéder à l’UI SearXNG depuis votre machine, dé-commentez la section `ports` du service `searxng` dans `docker-compose.yml`.
- Pour appeler l’API Crawl4AI depuis votre machine, dé-commentez la section `ports` du service `crawl4ai`.

## Notes de sécurité

- Ne commitez jamais `.env`
- Évitez d’exposer SearXNG / Crawl4AI sur Internet sans authentification et filtrage réseau

# Ambition et devenir : MCP Search & Browse (SearXNG + Crawl4AI) — self-hosted

Serveur **MCP** (Model Context Protocol) pour agents/LLM, basé sur le “simple browser” (style GPT-OSS) et rendu **fiable en self-host** grâce à :

- **SearXNG** : recherche web (meta-search)
- **Crawl4AI** : fetch/crawl headless (Chromium) + extraction **AI-ready** (markdown)
- **MCP server** : expose des tools “browser-like” (`search`, `open`, `find`) utilisables immédiatement par des agents

> Objectif : fournir une brique *web search + content fetch* stable et prédictible pour une plateforme LLM self-hosted (agents, RAG, deep research), tout en conservant la compatibilité avec le pattern “simple browser”.

---

## Fonctionnalités

- Recherche web via SearXNG (API JSON)
- Ouverture d’URL et extraction de contenu propre (markdown prioritaire) via Crawl4AI
- Tools MCP : `search`, `open`, `find`
- Stack 100% Docker
- Service **mcpo** inclus en **fallback** (proxy MCP), utile selon les intégrations

---

## Architecture (vue d’ensemble)

```text
Client LLM (vLLM / agent / etc.)
        |
        | MCP (SSE)
        v
mcp-browser (FastMCP) :8003
  - tool: search
  - tool: open
  - tool: find
        |
        | search -> searxng (interne docker)
        | fetch  -> crawl4ai (interne docker)
        v
SearXNG + Crawl4AI + Redis

Fallback (secondaire) :
mcpo (proxy MCP) :8004 -> http://mcp-browser:8003/sse
```

---

## Services Docker

Définis dans `docker-compose.yml` :

- `mcp-browser` : serveur MCP (expose `8003:8003`)
- `searxng` : moteur de recherche agrégé (**port non publié** par défaut)
- `crawl4ai` : service de scraping headless Chromium (**port non publié** par défaut)
- `redis` : cache / dépendance Crawl4AI
- `mcpo` : proxy MCP (expose `8004:8004`) — **service secondaire / fallback**

Remarque : SearXNG et Crawl4AI restent accessibles **uniquement** sur le réseau Docker `search-net` (sauf si vous publiez leurs ports).

---

## Prérequis

- Docker + Docker Compose

---

## Démarrage rapide (Docker only)

Depuis ce dossier :

```bash
docker compose up -d --build
```

Arrêt :

```bash
docker compose down
```

---

## Configuration (.env)

1) Créez votre fichier `.env` :

```bash
cp .env.example .env
```

2) Éditez `.env`.

Variables typiques utilisées par la stack :

- `SEARXNG_SECRET` : requis par SearXNG
- `SEARXNG_URL_EXT` : URL interne utilisée par `mcp-browser` (par défaut `http://searxng:8080`)
- `CRAWL4AI_URL_EXT` : URL interne utilisée par `mcp-browser` (par défaut `http://crawl4ai:8002`)
- `CRAWL4AI_API_TOKEN` : optionnel (si vous protégez Crawl4AI)
- `MCP_BROWSER_PORT` : port du serveur MCP (défaut `8003`)
- `MCP_BROWSER_HOST` : host d’écoute (défaut `0.0.0.0`)
- `CORS_ORIGINS` : origines autorisées (défaut `*`)
- `PROXY_URL` : optionnel (proxy côté Chromium / Crawl4AI)

---

## Endpoints

### Endpoint principal (recommandé)
- MCP SSE : **http://localhost:8003/sse**

### Endpoint secondaire / fallback (mcpo)
- Proxy MCP : **http://localhost:8004**

`mcpo` sert de wrapper/proxy vers `http://mcp-browser:8003/sse`. À utiliser seulement si votre intégration nécessite un proxy ou si vous voulez isoler l’accès.

---

## Tools MCP exposés (compat “simple browser”)

Le serveur `mcp-browser` expose :

- `search(query, topn=10, source=None)`
  - Recherche via l’API JSON de SearXNG
- `open(id, cursor, loc, num_lines, view_source=False, source=None)`
  - Ouvre un résultat (id) ou une URL (string) et renvoie un contenu lisible
  - Markdown prioritaire (fallback HTML si besoin)
- `find(pattern, cursor=-1)`
  - Recherche exacte d’un motif dans la page courante

---

## Connexion clients (pour l’instant)

### 1) vLLM (priorité) — via `--tool-server ...`

Vous pouvez brancher ce serveur MCP comme “tool server” pour vLLM.

- Endpoint recommandé :
  - `http://localhost:8003/sse`

- Fallback via mcpo :
  - `http://localhost:8004`

Exemple (à adapter selon votre version de vLLM et votre commande `serve`) :

```bash
vllm serve <MODEL> \
  --tool-server http://localhost:8003/sse
```

Si vous avez un besoin spécifique (proxy / compat), testez :

```bash
vllm serve <MODEL> \
  --tool-server http://localhost:8004
```

Notes :
- Selon les versions, vLLM peut attendre un format/transport précis côté tools. Dans ce repo, le transport exposé est **MCP SSE**.
- Si vous me donnez votre version vLLM + la commande exacte que vous utilisez, je peux te proposer la config finale “copier-coller”.

---

### 2) OpenWebUI (support “pour l’instant”)

Recommandation :
- Essayez d’abord une intégration MCP directe sur : `http://localhost:8003/sse`
- En cas de difficulté, utilisez le fallback `mcpo` : `http://localhost:8004`

Pourquoi `mcpo` ?
- `mcpo` est fourni par OpenWebUI (image `ghcr.io/open-webui/mcpo`) et sert souvent d’adaptateur/proxy entre OpenWebUI et des serveurs MCP.

---

### 3) LibreChat (support “pour l’instant”)

Même approche :
- Endpoint MCP principal : `http://localhost:8003/sse`
- Fallback proxy (mcpo) : `http://localhost:8004`

Si tu me dis quelle méthode d’intégration LibreChat tu utilises (MCP natif, plugin, proxy, etc.), je peux préciser le bloc de config exact.

---

## Dépannage

### Ports SearXNG / Crawl4AI non exposés
Par défaut, `searxng` et `crawl4ai` ne publient pas leurs ports sur `localhost`.

- Pour accéder à l’UI SearXNG depuis votre machine :
  - dé-commentez `ports:` dans le service `searxng` du `docker-compose.yml`
- Pour appeler l’API Crawl4AI depuis votre machine :
  - dé-commentez `ports:` dans le service `crawl4ai`

### Logs
- `crawl4ai` écrit des logs via le volume `./logs:/app/logs`
- Vous pouvez aussi consulter les logs docker :

```bash
docker compose logs -f --tail=200
```

---

## Notes de sécurité

- Ne commitez jamais `.env`
- Évitez d’exposer SearXNG / Crawl4AI / MCP sur Internet sans authentification + filtrage réseau
- Attention SSRF : un outil “fetch URL” peut être utilisé pour tenter d’accéder à des ressources internes si vous ne mettez pas de garde-fous (roadmap ci-dessous)

---

## TODO / Roadmap (proposition)

Objectif : passer d’un “bridge MCP minimal” à un **service de recherche web fiable pour agents**,
sans casser la compatibilité `search/open/find`.

### Phase 1 — Solidifier le socle (fiabilité)
- [ ] Ajouter un tool `health` (statut searxng/crawl4ai/redis + latences)
- [ ] Normaliser les erreurs (codes + messages actionnables) :
  - `SEARCH_BACKEND_UNAVAILABLE`, `FETCH_TIMEOUT`, `ANTI_BOT_BLOCKED`,
    `CONTENT_TOO_LARGE`, `UNSUPPORTED_MIME_TYPE`, `EMPTY_RESULT`, etc.
- [ ] Timeouts cohérents end-to-end + retry bornés
- [ ] Logging structuré (JSON) + request id / correlation id

### Phase 2 — Qualité de recherche (agents)
- [ ] Filtres de recherche : `allowed_domains`, `blocked_domains`, `language`, `freshness_days`
- [ ] Dédup / canonicalisation URL (strip trackers, paramètres inutiles)
- [ ] Reranking local (simple scoring hybride) pour améliorer l’ordre des résultats SearXNG

### Phase 3 — Contenu “LLM-ready”
- [ ] Modes d’extraction (`markdown`, `readable`, `links_only`, etc.)
- [ ] Chunking natif (chunks prêts pour RAG)
- [ ] Extraction structurée (schema/fields) en conservant la compat “browser-like”
- [ ] Support PDF (détection MIME + pipeline extraction + chunking)

### Phase 4 — Production (plateforme self-hosted)
- [ ] Cache intelligent (search + fetch + extraction) avec TTL
- [ ] Limites de concurrence / queue (éviter qu’un agent fasse tomber le service)
- [ ] Sécurité : garde-fous SSRF, allowlist/denylist, limites de taille
- [ ] Observabilité : métriques (Prometheus) + taux succès/erreurs + latences

### Phase 5 — Différenciation
- [ ] “Research sessions” (état, URLs vues, résumés intermédiaires)
- [ ] Connecteur RAG (Qdrant/pgvector/Weaviate) optionnel
- [ ] Stratégies par type de site (docs/news/forum/pdf-first)

---

## Licence

MIT