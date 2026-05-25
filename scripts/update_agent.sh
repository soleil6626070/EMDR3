#!/usr/bin/env bash
# Updates the existing EMDR agent in place using scripts/agent_workflow.json.
# PATCHes /v1/convai/agents/<agent_id> — same agent_id, no orphans.
# Use this after editing the workflow JSON.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
WORKFLOW_FILE="$REPO_ROOT/scripts/agent_workflow.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found" >&2; exit 1
fi
if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "error: $WORKFLOW_FILE not found" >&2; exit 1
fi

API_KEY="$(grep -E '^ELEVENLABS_API_EMDR_KEY[[:space:]]*=' "$ENV_FILE" \
  | sed -E 's/^ELEVENLABS_API_EMDR_KEY[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')"
AGENT_ID="$(grep -E '^ELEVENLABS_AGENT_ID_EMDR[[:space:]]*=' "$ENV_FILE" \
  | sed -E 's/^ELEVENLABS_AGENT_ID_EMDR[[:space:]]*=[[:space:]]*//' | tr -d '\r\n')"

if [[ -z "$API_KEY" ]]; then
  echo "error: ELEVENLABS_API_EMDR_KEY is empty" >&2; exit 1
fi
if [[ -z "$AGENT_ID" ]]; then
  echo "error: ELEVENLABS_AGENT_ID_EMDR is empty — run scripts/create_agent.sh first" >&2; exit 1
fi

API_URL="https://api.elevenlabs.io/v1/convai/agents/${AGENT_ID}"
echo "PATCHing $API_URL ..."

RESPONSE="$(curl -sS -X PATCH "$API_URL" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: $API_KEY" \
  --data-binary "@$WORKFLOW_FILE")"

RETURNED_ID="$(echo "$RESPONSE" | jq -r '.agent_id // empty')"
if [[ -z "$RETURNED_ID" ]]; then
  echo "error: update failed — response:" >&2
  echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
  exit 1
fi

echo "updated agent $RETURNED_ID"
