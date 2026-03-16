# 🔍 MCP Search & Browse Server

> Un serveur MCP (Model Context Protocol) qui donne à vos LLMs la capacité de **rechercher sur le web** et **naviguer des pages** en temps réel.

---

## 📐 Architecture

┌─────────────────────────────────────────────────────────┐
│                      CLIENT LLM                         │
│              (Claude, GPT, Agent custom)                │
└──────────────────────┬──────────────────────────────────┘
                       │  MCP (SSE / stdio)
                       ▼
┌─────────────────────────────────────────────────────────┐
│               MCP SIMPLE BROWSER SERVER                 │
│                    (Python · :8003)                     │
│                                                         │
│  Tools exposés :                                        │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐   │
│  │ search      │  │ open         │  │ find          │   │
│  └──────┬──────┘  └──────┬───────┘  └───────┬───────┘   │
└─────────┼────────────────┼──────────────────┼───────────┘
          │                │                  │
          ▼                ▼                  ▼
┌──────────────┐  ┌────────────────┐  ┌────────────────┐
│   SearXNG    │  │   Crawl4AI     │  │   Crawl4AI     │
│   (:8080)    │  │   (:8002)      │  │   (:8002)      │
│              │  │                │  │                │
│  Métamoteur  │  │  Headless      │  │  Headless      │
│  de recherche│  │  Browser       │  │  Browser       │
└──────────────┘  └────────────────┘  └────────────────┘


---

## 🔄 Flux de données

Utilisateur → LLM → MCP Server → SearXNG → Google/Bing/DuckDuckGo...
                                          ↓
                                   Résultats (JSON)
                                          ↓
                         MCP Server → Crawl4AI → Page HTML
                                          ↓
                                   Markdown propre
                                          ↓
                                  LLM ← Réponse enrichie


---

## 📁 Structure du projet

```
.
├── README.md
├── simple_browser_mcp_backend.md
├── docker-compose.yml
├── .env.example
├── .env
├── crawl4ai/
│   ├── Dockerfile
│   └── crawl4ai_service.py
├── gpt-oss-mcp-server/
│   ├── README.md
│   ├── build-system-prompt.py
│   ├── pyproject.toml
│   ├── python_server.py
│   └── reference-system-prompt.py
├── mcp-browser/
│   ├── Dockerfile
│   ├── browser_server.py
│   ├── pyproject.toml
│   ├── tests/
│   │   └── get_tools.py
│   └── tools/
│       ├── __init__.py
│       ├── tool.py
│       ├── simple_browser/
│       │   ├── __init__.py
│       │   ├── backend.py
│       │   ├── page_contents.py
│       │   └── simple_browser_tool.py
│       └── python_docker/
│           └── docker_tool.py
├── searxng/
│   └── settings.yml
└── logs/
```

---

## 🐳 Stack Docker

docker-compose.yml
│
├── searxng        (:8080)   — Moteur de recherche agrégé
├── crawl4ai       (:8002)  — Navigateur headless + extraction
└── mcp-browser    (:8003)   — Serveur MCP (point d'entrée)


---

## ⚡ Démarrage rapide

### 1. Cloner le repo

```bash
git clone https://github.com/ton-user/mcp-search-browser.git
cd mcp-search-browser
```

### 2. Configurer l'environnement
```bash
cp .env.example .env
```

# .env
```bash
SEARXNG_SECRET=<openssl rand -hex 32>
SEARXNG_URL_EXT=http://searxng:8080
CRAWL4AI_URL_EXT=http://crawl4ai:8002
CRAWL4AI_API_TOKEN=
MCP_BROWSER_PORT=8003
MCP_TRANSPORT=sse
OPENAI_API_KEY=sk-xxx    # optionnel
```

### 3. Lancer
```bash
docker compose up -d
```

### 4. Vérifier

| Service    | URL                 | Description             |
|------------|---------------------|-------------------------|
| SearXNG    | http://localhost:8080 | Interface web          |
| Crawl4AI   | http://localhost:8002 | API REST               |
| MCP Server | http://localhost:8003/sse | Endpoint SSE         |

---

## 🔧 Tools MCP disponibles

| Tool           | Description                               | Paramètres                        |
|----------------|-------------------------------------------|-----------------------------------|
| search         | Recherche web via SearXNG                 | query, topn, source               |
| open           | Visite une URL et retourne le markdown    | id, cursor, loc, num_lines, view_source, source |
| find           | Trouve un motif dans la page courante     | pattern, cursor                   |

---

## 🔌 Connexion avec un LLM

### Claude Desktop (claude_desktop_config.json)

```json
{
  "mcpServers": {
    "browser": {
      "url": "http://localhost:8003/sse"
    }
  }
}
```

---

## 🧪 Tests

```bash
# Unitaires
pytest tests/ -v

# Intégration (stack up requise)
pytest tests/test_integration.py -v
```

---

## 🛡️ Sécurité

- ❌ Ne jamais commit le .env
- ✅ SearXNG tourne en local, pas exposé publiquement
- ✅ Crawl4AI isolé dans le réseau Docker
- ✅ Pas de secrets dans le Dockerfile

---

## 📝 License

MIT