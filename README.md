[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/agentgateway-1?utm_medium=integration&utm_source=button&utm_campaign=agentgateway)

# Agentgateway on Railway

One-click Railway template for [Agentgateway](https://github.com/agentgateway/agentgateway) **v1.7.0**, the Linux Foundation's open-source proxy for AI agents: one OpenAI-compatible endpoint in front of your LLM providers, one MCP endpoint in front of your MCP servers, and a web UI with request logs, analytics, virtual keys and budgets.

## What it deploys

| Service | What it does | Port / health | State |
|---|---|---|---|
| Agentgateway (public) | Upstream's official image (`ghcr.io/agentgateway/agentgateway:v1.7.0`, pinned by digest) plus a small start script that writes the config from Railway variables | `$PORT` (8080), `GET /healthz` | Volume at `/data`: a SQLite database with the request logs, analytics, and everything you add in the UI (models, MCP servers, routes, virtual keys) |

On the public URL:

| Path | What | Auth |
|---|---|---|
| `/ui` | Admin UI (models, MCP servers, playgrounds, logs, analytics, keys) | Login: `ADMIN_USERNAME` / `ADMIN_PASSWORD` |
| `/v1/chat/completions`, `/v1/responses`, `/v1/messages`, `/v1/models` … | LLM gateway, forwards any model name to `LLM_BASE_URL` with your `LLM_API_KEY` | `Authorization: Bearer <AGENTGATEWAY_API_KEY>` or a virtual key made in the UI |
| `/mcp` (Streamable HTTP), `/sse` | MCP gateway: all MCP servers you add, merged into one | `Authorization: Bearer <AGENTGATEWAY_API_KEY>` |
| `/healthz` | Health check for Railway, returns `ok` | none |

Nothing that spends your key or shows your data is open: the UI needs the generated password, and the LLM and MCP endpoints need the generated gateway key.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `LLM_API_KEY` | (prompt) | **Required.** Your LLM provider's API key, for example an OpenAI key from https://platform.openai.com/api-keys. Stored only in Railway; the gateway sends it upstream, clients never see it |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | Any OpenAI-compatible endpoint (OpenRouter `https://openrouter.ai/api/v1`, Groq, DeepSeek, Together, a self-hosted vLLM or Ollama…) |
| `AGENTGATEWAY_API_KEY` | generated (48 chars) | The key your apps and MCP clients send as `Authorization: Bearer …` |
| `ADMIN_USERNAME` | `admin` | UI login name |
| `ADMIN_PASSWORD` | generated (24 chars) | UI login password. Change it in the Variables tab and redeploy to rotate it |
| `PORT` | `8080` | The gateway port; the public domain points at it |

Optional (not in the template, add them to the service if you want them):

| Variable | Default | Notes |
|---|---|---|
| `MCP_EXAMPLE` | `on` | `off` removes the example MCP server |
| `MCP_EXAMPLE_URL` | `https://mcp.deepwiki.com/mcp` | The example MCP server: DeepWiki's free public server (asks questions about public GitHub repos) |
| `AGW_DATABASE_URL` | `sqlite:///data/agentgateway.db` | Set it to `${{Postgres.DATABASE_URL}}` after adding a Railway Postgres if you run several replicas |
| `LOG_LEVEL` | `info` | `warn` for quieter logs |
| `WORKER_THREADS` | `2` | Gateway worker threads; raise it on bigger plans |

## After deploy

1. Open `https://YOUR-DOMAIN/ui` and log in with `ADMIN_USERNAME` and `ADMIN_PASSWORD` (Variables tab of the service).
2. Try the **LLM Playground** and the **MCP Playground** (paste `AGENTGATEWAY_API_KEY` as the bearer token there).
3. Point your apps at the gateway:

```sh
curl https://YOUR-DOMAIN/v1/chat/completions \
  -H "Authorization: Bearer $AGENTGATEWAY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.4-mini","messages":[{"role":"user","content":"Hello"}]}'
```

OpenAI SDKs: `base_url="https://YOUR-DOMAIN/v1"`, `api_key=<AGENTGATEWAY_API_KEY>`.

4. Connect an MCP client (Claude Code, Cursor, VS Code…) to `https://YOUR-DOMAIN/mcp`:

```json
{
  "mcpServers": {
    "agentgateway": {
      "type": "http",
      "url": "https://YOUR-DOMAIN/mcp",
      "headers": { "Authorization": "Bearer YOUR-AGENTGATEWAY-API-KEY" }
    }
  }
}
```

Claude Code: `claude mcp add --transport http agentgateway https://YOUR-DOMAIN/mcp --header "Authorization: Bearer YOUR-AGENTGATEWAY-API-KEY"`.

5. In the UI, add your own MCP servers (**MCP → Servers**, Streamable HTTP or SSE URLs), more models and providers (**LLM → Models**), per-app virtual keys with budgets (**LLM → API keys**) and routes. These are saved in the database on the volume and survive restarts and redeploys.

### How the config works

`start.sh` writes `/run/agw/config.yaml` from the variables at every start and runs agentgateway with `config.storage.mode: hybrid`. That file is the read-only baseline (gateway, login, gateway key, the `*` model and the example MCP server); what you add in the UI goes into the database on the volume and is layered on top. So the UI can't lock you out by removing the login, and a variable change takes effect on the next deploy. The UI says "file configuration is read-only" when you try to edit one of the baseline entries: change those with variables instead.

### Not included

- **Stdio MCP servers** (`npx …`, `uvx …`) need Node or Python in the container; this image has neither. Use servers that speak Streamable HTTP or SSE, or run a stdio server as its own Railway service behind an HTTP bridge.
- **OIDC/SSO login**, OpenTelemetry export, Kubernetes inference routing and the Kubernetes controller: set them up yourself if you need them ([docs](https://agentgateway.dev/docs/standalone/latest/)).

## Resources

The gateway is a Rust binary. On Railway with a 0.5 GB / 1 vCPU limit it used about 20–25 MB of memory idle and peaked at 36 MB while serving 400 LLM requests (50 at a time) plus real MCP tool calls, with no OOM kill. It fits Railway's smallest plan easily. If it ever stops unexpectedly it exits non-zero (a killed process exits 137), so Railway's on-failure restart brings it back.

## Updates

The service builds from this repository. When a new Agentgateway release is out, we bump the pinned image in the `Dockerfile` and add an entry to `CHANGELOG.md`. Railway then shows everyone who deployed the template an "update available" notice, and you choose when to apply it. Breaking changes are listed first in the changelog. Your data stays on the volume.

## Licence

Agentgateway is Apache-2.0 licensed by the Agentgateway authors (a Linux Foundation project). This wrapper is MIT.
