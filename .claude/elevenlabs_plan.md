                                           │
│ Plan: ElevenLabs TTS Integration via      │
│ lua-https                                 │
│                                           │
│ Context                                   │
│                                           │
│ EMDR3 needs to generate speech audio from │
│  text via the ElevenLabs API, then play   │
│ it back in-app. This is a core feature    │
│ for the cue-in script playback and "What  │
│ did you notice?" prompts. The user        │
│ previously had this working in a Python   │
│ version with a config.py + .env pattern.  │
│ We're recreating that architecture in     │
│ Love2D.                                   │
│                                           │
│ Step 0: Install system dependencies &     │
│ compile lua-https                         │
│                                           │
│ sudo apt install cmake libluajit-5.1-dev  │
│ libssl-dev libcurl4-openssl-dev           │
│                                           │
│ Then compile:                             │
│ cd /tmp                                   │
│ git clone                                 │
│ https://github.com/love2d/lua-https.git   │
│ cd lua-https                              │
│ cmake -Bbuild -S.                         │
│ -DCMAKE_BUILD_TYPE=Release                │
│ cmake --build build --target install      │
│ cp install/https.so                       │
│ /home/aidan/Projects/EMDR3/lib/https.so   │
│                                           │
│ Step 1: New file — config.lua (app        │
│ configuration)                            │
│                                           │
│ Mirrors the user's Python config.py       │
│ pattern. Loads .env for secrets, defines  │
│ app-level settings.                       │
│                                           │
│ -- config.lua                             │
│ local config = {}                         │
│                                           │
│ -- Parse .env file                        │
│ local contents =                          │
│ love.filesystem.read(".env")              │
│ if contents then                          │
│     for line in                           │
│ contents:gmatch("[^\r\n]+") do            │
│         if not line:match("^%s*#") and    │
│ line:match("=") then                      │
│             local key, value =            │
│ line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$") │
│             if key then config[key] =     │
│ value end                                 │
│         end                               │
│     end                                   │
│ end                                       │
│                                           │
│ -- API Keys (from .env)                   │
│ config.OPENAI_API_KEY    =                │
│ config.OPEN_AI_API_EMDR_KEY               │
│ config.ELEVENLABS_API_KEY =               │
│ config.ELEVENLABS_API_EMDR_KEY            │
│                                           │
│ -- ElevenLabs Settings                    │
│ config.ELEVENLABS_VOICE_ID  =             │
│ "21m00Tcm4TlvDq8ikWAM"  -- Rachel voice   │
│ config.ELEVENLABS_BASE_URL  =             │
│ "https://api.elevenlabs.io/v1"            │
│ config.ELEVENLABS_MODEL_ID  =             │
│ "eleven_multilingual_v2"                  │
│                                           │
│ return config                             │
│                                           │
│ Step 2: New file — modules/tts_thread.lua │
│  (worker thread)                          │
│                                           │
│ Runs in an isolated love.thread. Blocks   │
│ on a channel waiting for requests, POSTs  │
│ to ElevenLabs, pushes audio bytes (or     │
│ error) back.                              │
│                                           │
│ - Receives: { request_id, text, voice_id, │
│  api_key, base_url, model_id }            │
│ - Returns: { request_id, success, code,   │
│ data, error }                             │
│ - Gets love.filesystem.getSource() path   │
│ via a channel to set package.cpath for    │
│ lib/https.so                              │
│                                           │
│ Step 3: New file — modules/tts.lua        │
│ (main-thread API)                         │
│                                           │
│ Screens call tts.speak(text, callback).   │
│ Internally:                               │
│ - tts.init(config) — starts the worker    │
│ thread, sets up channels                  │
│ - tts.speak(text, opts, callback) —       │
│ pushes a request to the worker            │
│ - tts.update() — called every frame, pops │
│  completed responses, saves mp3 to Love2D │
│  save dir, creates love.audio.Source,     │
│ fires callback                            │
│                                           │
│ Audio saved to Love2D save directory      │
│ (~/.local/share/love/EMDR3/audio/).       │
│                                           │
│ Step 4: Modify main.lua                   │
│                                           │
│ - Add package.cpath adjustment for lib/   │
│ at the top                                │
│ - require("modules.tts")                  │
│ - require("config")                       │
│ - In love.load(): call tts.init(config)   │
│ - In love.update(dt): call tts.update()   │
│                                           │
│ Step 5: Modify conf.lua                   │
│                                           │
│ - Add t.modules.thread = true (explicit)  │
│ - Update version "11.4" → "11.5"          │
│                                           │
│ Step 6: Modify .gitignore                 │
│                                           │
│ - Add lib/*.so and lib/*.dll              │
│ (platform-specific compiled binaries)     │
│                                           │
│ Files summary                             │
│                                           │
│ File: config.lua                          │
│ Action: CREATE                            │
│ Purpose: App config + .env parsing        │
│ ────────────────────────────────────────  │
│ File: modules/tts.lua                     │
│ Action: CREATE                            │
│ Purpose: Main-thread TTS API              │
│ ────────────────────────────────────────  │
│ File: modules/tts_thread.lua              │
│ Action: CREATE                            │
│ Purpose: Worker thread for HTTP calls     │
│ ────────────────────────────────────────  │
│ File: lib/https.so                        │
│ Action: BUILD                             │
│ Purpose: Compiled lua-https               │
│ ────────────────────────────────────────  │
│ File: main.lua                            │
│ Action: MODIFY                            │
│ Purpose: Wire up config, tts init,        │
│   tts.update                              │
│ ────────────────────────────────────────  │
│ File: conf.lua                            │
│ Action: MODIFY                            │
│ Purpose: Enable thread module, fix        │
│ version                                   │
│ ────────────────────────────────────────  │
│ File: .gitignore                          │
│ Action: MODIFY                            │
│ Purpose: Exclude compiled binaries        │
│                                           │
│ Usage from screens                        │
│                                           │
│ local tts = require("modules.tts")        │
│                                           │
│ tts.speak("What did you notice during     │
│ that set?", nil, function(success,        │
│ source, err)                              │
│     if success then                       │
│         love.audio.play(source)           │
│     else                                  │
│         print("TTS error: " ..            │
│ tostring(err))                            │
│     end                                   │
│ end)                                      │
│                                           │
│ Verification                              │
│                                           │
│ 1. Run love . from project root — app     │
│ should start without errors               │
│ 2. Add a temporary test: in menu.lua,     │
│ trigger tts.speak() on a keypress (e.g.   │
│ "t")                                      │
│ 3. Verify: audio plays back after a short │
│  delay (network round-trip)               │
│ 4. Check ~/.local/share/love/EMDR3/audio/ │
│  for the saved mp3                        │
│ 5. Check console for any thread errors    │
│                                           │
│ Unresolved questions                      │
│                                           │
│ 1. JSON encoding robustness —             │
│ string.format works for simple text but   │
│ will break on quotes/newlines/backslashes │
│  in input. Should we add a pure-Lua JSON  │
│ library (like dkjson, single file) now,   │
│ or keep string.format and add it later    │
│ when LLM integration also needs it?       │
│ 2. Voice selection — Rachel               │
│ (21m00Tcm4TlvDq8ikWAM) is hardcoded in    │
│ config.lua. Are you happy with that       │
│ voice, or do you want to try others first │
│  via the ElevenLabs dashboard?            │
│ 3. Error handling UX — if the API call    │
│ fails (no internet, bad key, rate limit), │
│  should the app show an on-screen         │
│ message, or is a console print sufficient │
│  for now?                