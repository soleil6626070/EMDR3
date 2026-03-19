# EMDR3 - rewrite in Lua using the Love2D framework.

A therapeutic (E)ye (M)ovement (D)esensitisation & (R)eprocessing tool built with Lua and the LOVE2D framework.

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

## Screen Flow

- Main menu → Target Image selection → pre user rating → cue in script → processing cycles → post user rating

## Key Data Structures
- We will save the users' responses in a linked list of {cycle, response_text} nodes
