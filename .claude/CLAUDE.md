# EMDR3 - rewrite in Lua using the Love2D framework.

A therapeutic (E)ye (M)ovement (D)esensitisation & (R)eprocessing tool built with Lua and the LOVE2D framework.

## Planning mode

- At the end of each plan, give me a list of unresolved questions to answer, if any. 

## Tech Stack
- **Language:** Lua
- **Framework:** LOVE2D (2D game framework)
- **Audio recording service** Undecided
- **Transcription Service** Whisper (local, GPU if    
  available)   
- **TTS** ElevenLabs API                          
- **LLM for cue in script generation**  Undecided

## Context7 Documentation
Only use context7 when explicitly asked. Specify which library IDs to use per prompt.

Available library IDs:
- LOVE2D wiki: `/websites/love2d_wiki`
- ElevenLabs API: `/websites/elevenlabs_io`
- lua-http (HTTP requests): `/daurnimator/lua-http` (note: `lua-https` is not indexed in context7; use this as the closest alternative)

## Screen Flow

- Main menu → Target Image selection → pre user rating → cue in script → processing cycles → post user rating

## Key Data Structures
- We will save the users' responses in a linked list of {cycle, response_text} nodes

## Target Application Flow

```mermaid

graph TD
    Start([App Start]) --> Menu[Menu Screen]

    Menu -->|Option 1| TID[Target Identification]
    Menu -->|Option 2| TS[Target Selection]

    TID --> Q1[Question 1:<br/>Recording]
    Q1 --> T1[Transcribing]
    T1 --> Q2[Question 2:<br/>Recording]
    Q2 --> T2[Transcribing]
    T2 --> Q3[Question 3:<br/>Recording]
    Q3 --> T3[Transcribing]
    T3 --> Q4[Question 4:<br/>Recording]
    Q4 --> T4[Transcribing]
    T4 --> Q5[Question 5:<br/>Recording]
    Q5 --> T5[Transcribing]
    T5 --> TI_TXT[Target Image txt file containing responses created]

    TS --> PreD[Pre-Distress Rating]
    PreD --> TQ

    PreD --> ScriptQ[Does the Cue-In Script exist?]
    ScriptQ -->|Yes| CIR
    ScriptQ -->|No| CIG[LLM API generates a cue-in script from the target_image.txt]
    CIG --> CIR[Cue-In Review]
    CIR -->|Edit| CIG
    CIR -->|Accept| AudioQ[Does the Cue-In audio exist?]
    AudioQ -->|Yes| CIA[Cue-In Audio]
    AudioQ -->|No| CIAG[ElevenLabs API to generate audio]-->CIA


    CIA --> PC{Processing<br/>Cycles}

    PC --> Osc[Oscillating Circle <br/>n seconds]
    Osc --> PR[Play What did you notice? soundbite <br/> + record user response]
    PR --> FB[Feedback Display]
    PR --> TQ[Add saved audio to background transcription worker queue]
    TQ --> Transc[Transcribe user responses in response order]
    Transc --> LL[Save transcribed response to linked list]

    FB -->|Cycle < Total| PC
    FB -->|Cycle = Total| PostD[Post-Distress Rating]

    PostD --> Fade[Fading Screen]
    PostD --> TQ
    Fade --> Menu

    style Menu fill:#4a90e2
    style TID fill:#7cb342
    style TS fill:#7cb342
    style PC fill:#ff9800
    style Osc fill:#ff9800
    style PR fill:#ff9800
    style FB fill:#ff9800
    style PreD fill:#9c27b0
    style PostD fill:#9c27b0
    style CIG fill:#e91e63
    style CIR fill:#e91e63
    style CIA fill:#e91e63
```

## Potential Optimisations

- **`noticed.lua` wdyn directory scan:** Currently rescans `resources/audio/wdyn/` on every `noticed.load()` call (~60 times per session). Cost is negligible on SSD with ≤10 files (~3ms/session total). Cache the file list at startup if: files exceed ~30–35, cycles exceed ~200, or running on a spinning HDD (threshold drops to ~2 files at ~1ms/scan).
