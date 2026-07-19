#!/usr/bin/env bash
# Emits the final ElevenLabs agent payload to stdout:
# scripts/agent_workflow.json with the system prompt injected from
# prompts/agent_target_image.md (everything after its first '---' line — the
# file's header note is not sent) and the first message injected from
# prompts/agent_first_message.txt.
#
# Used by create_agent.sh and update_agent.sh; run directly to inspect what
# would be sent.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_FILE="$REPO_ROOT/scripts/agent_workflow.json"
PROMPT_FILE="$REPO_ROOT/prompts/agent_target_image.md"
FIRST_FILE="$REPO_ROOT/prompts/agent_first_message.txt"

for f in "$WORKFLOW_FILE" "$PROMPT_FILE" "$FIRST_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "error: $f not found" >&2; exit 1
  fi
done

PROMPT="$(awk 'f{print} /^---$/{f=1}' "$PROMPT_FILE")"
FIRST="$(cat "$FIRST_FILE")"

if [[ -z "$PROMPT" ]]; then
  echo "error: no prompt content found after the first '---' line in $PROMPT_FILE" >&2
  exit 1
fi

jq --arg prompt "$PROMPT" --arg first "$FIRST" \
  '.conversation_config.agent.prompt.prompt = $prompt
   | .conversation_config.agent.first_message = ($first | rtrimstr("\n"))' \
  "$WORKFLOW_FILE"
