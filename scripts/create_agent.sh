#!/usr/bin/env bash
# Creates the EMDR Target Identification agent on ElevenLabs.
# Reads ELEVENLABS_API_EMDR_KEY from .env, POSTs scripts/agent_workflow.json
# to /v1/convai/agents/create, and writes the returned agent_id back into .env
# under ELEVENLABS_AGENT_ID_EMDR=.
#
# Re-running this script creates a NEW agent (does not update the existing one).
# To update an existing agent, use scripts/update_agent.sh (not yet written).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
WORKFLOW_FILE="$REPO_ROOT/scripts/agent_workflow.json"
API_URL="https://api.elevenlabs.io/v1/convai/agents/create"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found" >&2
  exit 1
fi
if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo "error: $WORKFLOW_FILE not found" >&2
  exit 1
fi

# Parse ELEVENLABS_API_EMDR_KEY out of .env (handles "KEY= value" with optional spaces).
API_KEY="$(grep -E '^ELEVENLABS_API_EMDR_KEY[[:space:]]*=' "$ENV_FILE" \
  | sed -E 's/^ELEVENLABS_API_EMDR_KEY[[:space:]]*=[[:space:]]*//' \
  | tr -d '\r\n')"

if [[ -z "$API_KEY" ]]; then
  echo "error: ELEVENLABS_API_EMDR_KEY is empty in $ENV_FILE" >&2
  exit 1
fi

echo "Posting workflow to $API_URL ..."

RESPONSE="$(curl -sS -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: $API_KEY" \
  --data-binary "@$WORKFLOW_FILE")"

# Pretty-print response for the user.
echo "--- API response ---"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
echo "--------------------"

AGENT_ID="$(echo "$RESPONSE" | jq -r '.agent_id // empty')"

if [[ -z "$AGENT_ID" ]]; then
  echo "error: no agent_id in response — agent NOT created" >&2
  exit 1
fi

# Write agent_id back into .env. Replaces the existing ELEVENLABS_AGENT_ID_EMDR line.
if grep -qE '^ELEVENLABS_AGENT_ID_EMDR[[:space:]]*=' "$ENV_FILE"; then
  # Use a sed delimiter that won't appear in an agent_id (which is alphanumeric).
  sed -i "s|^ELEVENLABS_AGENT_ID_EMDR[[:space:]]*=.*|ELEVENLABS_AGENT_ID_EMDR=${AGENT_ID}|" "$ENV_FILE"
else
  echo "ELEVENLABS_AGENT_ID_EMDR=${AGENT_ID}" >> "$ENV_FILE"
fi

echo "agent_id: $AGENT_ID"
echo "wrote ELEVENLABS_AGENT_ID_EMDR to $ENV_FILE"
