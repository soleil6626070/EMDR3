#!/usr/bin/env bash
# Updates the existing EMDR agent in place. PATCHes /v1/convai/agents/<agent_id>
# with the payload from build_agent_payload.sh (agent_workflow.json + the system
# prompt from prompts/agent_target_image.md + first message from
# prompts/agent_first_message.txt). Use after editing any of those files.
# After updating, run fetch_agent.sh and diff to confirm the PATCH fully
# replaced the old config (especially that no workflow node graph remains).

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

PAYLOAD="$(mktemp)"
trap 'rm -f "$PAYLOAD"' EXIT
"$REPO_ROOT/scripts/build_agent_payload.sh" > "$PAYLOAD"

API_URL="https://api.elevenlabs.io/v1/convai/agents/${AGENT_ID}"
echo "PATCHing $API_URL ..."

RESPONSE="$(curl -sS -X PATCH "$API_URL" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: $API_KEY" \
  --data-binary "@$PAYLOAD")"

RETURNED_ID="$(echo "$RESPONSE" | jq -r '.agent_id // empty')"
if [[ -z "$RETURNED_ID" ]]; then
  echo "error: update failed — response:" >&2
  echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
  exit 1
fi

echo "updated agent $RETURNED_ID"
