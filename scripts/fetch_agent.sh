#!/usr/bin/env bash
# Pulls the current agent config from ElevenLabs and overwrites
# scripts/agent_workflow.json. Use this after editing in the dashboard.
#
# A backup of the current local file is written to scripts/agent_workflow.json.bak

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
WORKFLOW_FILE="$REPO_ROOT/scripts/agent_workflow.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found" >&2; exit 1
fi

API_KEY="$(grep -E '^ELEVENLABS_API_EMDR_KEY[[:space:]]*=' "$ENV_FILE" \
  | sed -E 's/^ELEVENLABS_API_EMDR_KEY[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')"
AGENT_ID="$(grep -E '^ELEVENLABS_AGENT_ID_EMDR[[:space:]]*=' "$ENV_FILE" \
  | sed -E 's/^ELEVENLABS_AGENT_ID_EMDR[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')"

if [[ -z "$API_KEY" ]]; then
  echo "error: ELEVENLABS_API_EMDR_KEY is empty" >&2; exit 1
fi
if [[ -z "$AGENT_ID" ]]; then
  echo "error: ELEVENLABS_AGENT_ID_EMDR is empty" >&2; exit 1
fi

API_URL="https://api.elevenlabs.io/v1/convai/agents/${AGENT_ID}"
echo "GET $API_URL ..."

RESPONSE="$(curl -sS -X GET "$API_URL" -H "xi-api-key: $API_KEY")"

# Sanity-check the response has an agent_id.
RETURNED_ID="$(echo "$RESPONSE" | jq -r '.agent_id // empty')"
if [[ -z "$RETURNED_ID" ]]; then
  echo "error: fetch failed — response:" >&2
  echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
  exit 1
fi

# Backup current local file, then overwrite.
if [[ -f "$WORKFLOW_FILE" ]]; then
  cp "$WORKFLOW_FILE" "$WORKFLOW_FILE.bak"
  echo "backed up old file to $WORKFLOW_FILE.bak"
fi

echo "$RESPONSE" | jq . > "$WORKFLOW_FILE"
echo "wrote $WORKFLOW_FILE"
