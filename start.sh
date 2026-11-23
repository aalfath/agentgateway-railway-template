#!/bin/sh
# Writes agentgateway's configuration from Railway variables at every start, then runs agentgateway.
# The file is a read-only baseline (hybrid storage): changes made in the UI are stored in the
# database on the volume, so they survive restarts, and the login and keys below can't be removed
# from the UI by mistake.
set -eu

fail() { echo "start.sh: $*" >&2; exit 1; }

PORT="${PORT:-8080}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
AGENTGATEWAY_API_KEY="${AGENTGATEWAY_API_KEY:-}"
LLM_API_KEY="${LLM_API_KEY:-}"
LLM_BASE_URL="${LLM_BASE_URL:-https://api.openai.com/v1}"
AGW_DATABASE_URL="${AGW_DATABASE_URL:-sqlite:///data/agentgateway.db}"
MCP_EXAMPLE="${MCP_EXAMPLE:-on}"
MCP_EXAMPLE_URL="${MCP_EXAMPLE_URL:-https://mcp.deepwiki.com/mcp}"
LOG_LEVEL="${LOG_LEVEL:-info}"
DATA_DIR="${DATA_DIR:-/data}"
RUN_DIR=/run/agw
AGW_UID=65532

[ -n "$ADMIN_PASSWORD" ] || fail "ADMIN_PASSWORD is empty. Set it on the service (Variables tab) and redeploy."
[ -n "$AGENTGATEWAY_API_KEY" ] || fail "AGENTGATEWAY_API_KEY is empty. Set it on the service (Variables tab) and redeploy."
[ "${#ADMIN_PASSWORD}" -ge 12 ] || fail "ADMIN_PASSWORD must be at least 12 characters."
[ "${#AGENTGATEWAY_API_KEY}" -ge 24 ] || fail "AGENTGATEWAY_API_KEY must be at least 24 characters."
case "$PORT" in ''|*[!0-9]*) fail "PORT must be a number." ;; esac
# These values are substituted into YAML, so keep them to safe characters.
for pair in "ADMIN_USERNAME=$ADMIN_USERNAME" "AGENTGATEWAY_API_KEY=$AGENTGATEWAY_API_KEY"; do
  case "${pair#*=}" in *[!A-Za-z0-9._-]*) fail "${pair%%=*} may only contain letters, digits, '.', '_' and '-'." ;; esac
done
case "$ADMIN_PASSWORD" in *[\"\\:]*|*' '*) fail "ADMIN_PASSWORD must not contain spaces, quotes, backslashes or ':'." ;; esac
case "$LLM_BASE_URL" in http://*|https://*) ;; *) fail "LLM_BASE_URL must start with http:// or https://." ;; esac
case "$MCP_EXAMPLE_URL" in http://*|https://*) ;; *) fail "MCP_EXAMPLE_URL must start with http:// or https://." ;; esac
case "$LLM_BASE_URL$AGW_DATABASE_URL$MCP_EXAMPLE_URL" in *[\"\\\ \$]*) fail "LLM_BASE_URL AGW_DATABASE_URL and MCP_EXAMPLE_URL must not contain quotes, backslashes, spaces or '\$'." ;; esac

mkdir -p "$DATA_DIR" "$RUN_DIR"
chown "$AGW_UID:$AGW_UID" "$DATA_DIR"
umask 077

# Basic-auth login for the UI ({SHA} htpasswd entry). The password itself is never written to disk.
sha=$(printf '%s' "$ADMIN_PASSWORD" | sha1sum | cut -c1-40 | xxd -r -p | base64)
printf '%s:{SHA}%s\n' "$ADMIN_USERNAME" "$sha" > "$RUN_DIR/htpasswd"

if [ -n "$LLM_API_KEY" ]; then
  printf '%s' "$LLM_API_KEY" > "$RUN_DIR/llm-key"
  MODELS=$(cat <<YAML
  models:
  # Any model name the client sends is passed through to LLM_BASE_URL (OpenAI-compatible).
  - name: "*"
    provider: openAI
    params:
      baseUrl: "${LLM_BASE_URL}"
      apiKey:
        file: ${RUN_DIR}/llm-key
YAML
)
else
  MODELS="  models: []"
fi

if [ "$MCP_EXAMPLE" = "off" ]; then
  TARGETS="  targets: []"
else
  TARGETS=$(cat <<YAML
  targets:
  # Example target: DeepWiki's free public MCP server (documentation for public GitHub repos).
  - name: deepwiki
    mcp:
      host: "${MCP_EXAMPLE_URL}"
YAML
)
fi

cat > "$RUN_DIR/config.yaml" <<YAML
# yaml-language-server: \$schema=https://agentgateway.dev/schema/config
# Written by /app/start.sh at every start from the Railway variables. Do not edit: changes made
# in the UI are stored in the database instead (config.storage.mode: hybrid).
config:
  storage:
    mode: hybrid
  database:
    url: "\${AGW_DATABASE_URL}"
  logging:
    level: ${LOG_LEVEL}
gateways:
  default:
    port: ${PORT}
routes:
# Health check for Railway (no login needed, returns only "ok").
- name: railway-healthz
  matches:
  - path:
      exact: /healthz
  policies:
    directResponse:
      status: 200
      body: "ok"
ui:
  gateways: default
  policies:
    basicAuth:
      mode: strict
      realm: Agentgateway
      htpasswd:
        file: ${RUN_DIR}/htpasswd
llm:
  policies:
    apiKey:
      mode: strict
      keys:
      - key: "\${AGENTGATEWAY_API_KEY}"
        metadata:
          name: railway-gateway-key
${MODELS}
mcp:
  failureMode: failOpen
  policies:
    apiKey:
      mode: strict
      keys:
      - key: "\${AGENTGATEWAY_API_KEY}"
        metadata:
          name: railway-gateway-key
${TARGETS}
YAML

chown -R "$AGW_UID:$AGW_UID" "$RUN_DIR"
export AGW_DATABASE_URL AGENTGATEWAY_API_KEY
# Railway hosts have many CPUs; size the runtime to the service, not the host.
export WORKER_THREADS="${WORKER_THREADS:-2}"
unset ADMIN_PASSWORD LLM_API_KEY

echo "start.sh: agentgateway $(/app/agentgateway -V 2>/dev/null || echo v1.7.0) on port $PORT, data in $DATA_DIR"
exec chpst -u nonroot:nonroot /app/agentgateway -f "$RUN_DIR/config.yaml"
