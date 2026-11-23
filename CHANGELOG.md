# Changelog

## 1.7.0 (2026-11-23)

First release of the template.

- Agentgateway v1.7.0, official image `ghcr.io/agentgateway/agentgateway:v1.7.0@sha256:60216aafb03d37f94e952ff3d51d2f630a65b10ecaebdc0a864882f92610c45b`.
- One public gateway on `$PORT` serving the UI (`/ui`, basic-auth login), the LLM API (`/v1/...`) and MCP (`/mcp`, `/sse`), both locked with a generated bearer key, and `/healthz` for Railway.
- Hybrid config storage: the start script writes the baseline config from variables; UI changes, request logs and analytics live in SQLite on the `/data` volume.
- Example MCP server: DeepWiki (`https://mcp.deepwiki.com/mcp`), turn off with `MCP_EXAMPLE=off`.
