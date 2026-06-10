# EMDR3

A therapeutic Eye Movement Desensitisation & Reprocessing tool built with Lua and the LÖVE2D framework.

---

## User Experience Flow

```mermaid
flowchart TD
    Start([Launch App]) --> Menu[Main Menu]

    Menu -->|Target Identification| TII[Talk with ElevenLabs\nconversational AI agent\nabout your target memory]
    TII -->|Save transcript| BG[Background: LLM generates\ncue-in script + TTS audio]
    BG --> Menu

    Menu -->|Start Session| TS[Target Select\nPick a saved target image]
    TS -->|R — review| Review[Review / edit\ncue-in script\nRegenerate audio]
    Review --> TS

    TS -->|Enter| Confirm[Are you ready\nto begin?]
    Confirm -->|Enter| CueIn[Cue-in script plays\nanchors you to target memory]
    CueIn --> Osc[Oscillating dot\nbilateral stimulation]
    Osc --> WDN[What did you notice?\nauto-records your response]
    WDN -->|Space| NT[Notice that...\nshort fade]
    NT -->|next cycle| Osc
    NT -->|final cycle| Menu
```

---

## Technical Flow

```mermaid
flowchart TD
    subgraph main["main.lua — love callbacks"]
        Load["love.load()\ninit all modules"] 
        Update["love.update(dt)\ntts / transcription /\nagent / cue_in / screen"]
        Draw["love.draw()\ncurrent screen"]
        KP["love.keypressed(k)\nlove.textinput(t)"]
    end

    subgraph screens["Screens"]
        Menu["menu.lua"]
        TID["target_identification.lua\nstreams mic → agent"]
        TSel["target_select.lua\nscans output_data/targets/"]
        CIR["cue_in_review.lua\nedit script + regen audio"]
        Osc["oscillating.lua\nconfirm → cue_in → normal\n→ slowing → breathe"]
        Noticed["noticed.lua\nplay wdyn audio + record"]
        NT["notice_that.lua\nfade + nextCycle()"]
    end

    subgraph modules["Modules — main thread APIs"]
        Agent["agent.lua\nconversational AI state"]
        TTS["tts.lua\nElevenLabs TTS requests"]
        Trans["transcription.lua\nwhisper job queue"]
        CueIn["cue_in.lua\nLLM → script → TTS pipeline"]
    end

    subgraph threads["Worker Threads"]
        AgentT["agent_thread.lua\nWebSocket ↔ ElevenLabs\nConversational AI"]
        TTST["tts_thread.lua\nPOST → ElevenLabs\nTTS API"]
        TransT["transcription_thread.lua\nruns whisper-cli"]
        CueInT["cue_in_thread.lua\nPOST → OpenAI/Anthropic\nPOST → ElevenLabs TTS\nsaves targets/ folder"]
    end

    subgraph storage["Filesystem"]
        OutData["output_data/\ntarget_image_*.txt — raw TII transcripts"]
        Targets["output_data/targets/\n slug/transcript.txt\n slug/script.txt\n slug/cue_in.mp3"]
        Queue["resources/audio/\ntranscription_queue/ — response WAVs"]
        Wdyn["resources/audio/wdyn/ — wdyn variants"]
    end

    Load --> Agent & TTS & Trans & CueIn
    Agent <-->|channels| AgentT
    TTS <-->|channels| TTST
    Trans <-->|channels| TransT
    CueIn <-->|channels| CueInT

    TID --> Agent
    TID -->|transcript text| CueIn
    CueInT --> Targets
    TSel --> Targets
    Osc -->|cue_in.mp3| Load
    Noticed --> Trans
    Trans --> Queue
    TransT --> Queue
```

---

## Session Log

### Session — 2026-06-10

**WebSocket busy-spin fix (`lib/websocket.lua`)**
The `read_bytes` loop spun at 100% CPU on a single core while waiting for WebSocket data, because the `wantread`/`wantwrite` branch had no sleep. Fixed with `socket.sleep(0.001)` in that branch — drops idle CPU to near zero with negligible latency cost.

**Cue-in script generation pipeline**
Built the full pipeline from TII transcript → cue-in audio file:
- `modules/cue_in.lua` — main-thread API (same pattern as `tts.lua`)
- `modules/cue_in_thread.lua` — background worker: calls OpenAI (or Anthropic) to generate a Shapiro-protocol cue-in script + slug name, saves `output_data/targets/<slug>/`, then calls ElevenLabs TTS to produce `cue_in.mp3`
- LLM prompt follows Phase 4 Shapiro protocol: image → NC verbatim → body location, 1–3 sentences
- Config fields added: `LLM_PROVIDER`, `LLM_MODEL`, `ANTHROPIC_API_KEY`, `TARGETS_DIR`

**Target selection screen (`screens/target_select.lua`)**
Replaces the direct "Start Session → oscillating" flow. Scans `output_data/targets/` and lists available targets by slug name. `T` key triggers generation from the most recent transcript (dev shortcut).

**Cue-in review screen (`screens/cue_in_review.lua`)**
Lets the user read, edit (live typing), and regenerate the TTS audio for any saved target without re-running the LLM.

**Session start flow (`screens/oscillating.lua`)**
Added `"confirm"` and `"playing_cue_in"` phases before the first oscillation cycle. Shows "Are you ready to begin?" → Enter → plays `cue_in.mp3` → oscillation starts when audio finishes. Subsequent cycles skip straight to oscillation.

**Bug fix — oscillating screen re-showing confirm on every cycle**
`oscillating.load()` was entering `"confirm"` phase unconditionally, so every return from `notice_that` showed the confirmation screen again. Fixed by only entering `"confirm"` when `session.currentCycle <= 1`.
