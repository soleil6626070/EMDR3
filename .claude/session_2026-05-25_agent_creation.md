# Session 2026-05-25 — ElevenLabs Agent Created

## Files

- `scripts/agent_workflow.json` (new) — workflow definition. Edit to change agent behaviour.
- `scripts/create_agent.sh` (new) — POSTs workflow JSON to `/v1/convai/agents/create`, writes returned `agent_id` to `.env`. Re-running creates a new agent.
- `.env` (modified) — `ELEVENLABS_AGENT_ID_EMDR=agent_7801kse4q3eee53rwb063te925xb`

## Workflow shape

`start → intro → event → image → neg_cog → pos_cog → voc → emotion → sud → body → end`

- Each stage = `override_agent` subagent node with stage-specific `additional_prompt`.
- Transitions: `forward_condition: { type: "llm", condition: "..." }` — LLM judges completion.
- Base persona prompt in `conversation_config.agent.prompt.prompt`.
- Voice: Sarah (`EXAVITQu4vr4xnSDxMaL`), turbo_v2, speed 0.95. LLM: gemini-2.5-flash (default).

## Test

```
love .
# Menu → Target Identification
# Escape ends, Enter saves transcript to output_data/target_image_<timestamp>.txt
```

## Notes

- Re-running `create_agent.sh` orphans the old agent — write `update_agent.sh` (PATCH) later if it gets noisy.
- WebSocket client (`modules/agent_thread.lua`) was already working; today only filled in the missing `agent_id`.
- Auth uses `xi-api-key` header from `.env`. SaaS-with-signed-URLs later = ~10 line change in `agent_thread.lua` + small backend.
- Agent collects SUD + VOC in conversation; existing `PreD`/`PostD` screens still run. Decide later which is source of truth.
- `testing/` is now gitignored.
